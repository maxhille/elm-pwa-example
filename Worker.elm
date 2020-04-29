port module Worker exposing
    ( ClientMessage(..)
    , ClientState
    , Login(..)
    , Subscription(..)
    , User
    , logout
    , main
    , onClientUpdate
    , sendMessage
    )

import IndexedDB as DB
import Json.Decode as JD
import Json.Encode as JE
import Permissions as P
import Platform
import ServiceWorker as SW


port getVapidKey : () -> Cmd msg


port onVapidkeyResult : (String -> msg) -> Sub msg


port sendLogin : JE.Value -> Cmd msg


port saveSubscription : JE.Value -> Cmd msg


port getSubscription : JE.Value -> Cmd msg


port getSubscriptionReply : (Bool -> msg) -> Sub msg


port onLoginResult : (JD.Value -> msg) -> Sub msg


main : Program () Model Msg
main =
    Platform.worker
        { init = init
        , subscriptions = subscriptions
        , update = logUpdate extendedUpdate
        }


type alias Model =
    { subscription : Maybe Bool
    , vapidKey : Maybe String
    , permissionStatus : Maybe P.PermissionStatus
    , login : Maybe Login
    , db : Maybe DB.DB
    , authSaved : Bool
    }


type Msg
    = OnDBOpen ( DB.DB, DB.OpenResponse )
    | OnClientMessage (Result JD.Error ClientMessage)
    | VapidkeyResult String
    | PermissionChange P.PermissionStatus
    | StoreCreated (Result JD.Error DB.ObjectStore)
    | QueryResult DB.QueryResult
    | LoginResult (Result JD.Error Login)
    | NewSubscription (Result JD.Error Subscription)
    | HasSubscription Bool


type Login
    = LoggedOut
    | LoggedIn User


type alias User =
    { name : String
    , token : String
    }


type ClientMessage
    = Subscribe String
    | Hello
    | Login String
    | Logout


type alias ClientState =
    { subscription : Maybe Bool
    , vapidKey : Maybe String
    , permissionStatus : Maybe P.PermissionStatus
    , login : Maybe Login
    }


onClientUpdate : (Result JD.Error ClientState -> msg) -> Sub msg
onClientUpdate msg =
    SW.onMessage
        (JD.decodeValue decodeClientState >> msg)


encodeMaybeString : Maybe String -> JE.Value
encodeMaybeString ms =
    maybeNull JE.string ms


maybeNull : (a -> JE.Value) -> Maybe a -> JE.Value
maybeNull encoder maybe =
    case maybe of
        Nothing ->
            JE.null

        Just a ->
            encoder a


encodeSubscriptionData : SubscriptionData -> JE.Value
encodeSubscriptionData data =
    JE.object
        [ ( "auth", JE.string data.auth )
        , ( "p256dh", JE.string data.p256dh )
        , ( "endpoint", JE.string data.endpoint )
        ]


encodeLogin : Maybe Login -> JE.Value
encodeLogin maybe =
    case maybe of
        Nothing ->
            JE.null

        Just login ->
            case login of
                LoggedIn data ->
                    JE.object
                        [ ( "type", JE.string "logged-in" )
                        , ( "name", JE.string data.name )
                        , ( "token", JE.string data.token )
                        ]

                LoggedOut ->
                    JE.object
                        [ ( "type", JE.string "logged-out" )
                        ]


decodeLogin : JD.Decoder Login
decodeLogin =
    JD.field "type" JD.string
        |> JD.andThen
            (\typ ->
                case typ of
                    "logged-in" ->
                        JD.map2 (\name token -> LoggedIn { name = name, token = token })
                            (JD.field "name" JD.string)
                            (JD.field "token" JD.string)

                    "logged-out" ->
                        JD.succeed LoggedOut

                    _ ->
                        JD.fail <| "unknown message: " ++ typ
            )


type Subscription
    = NoSubscription
    | Subscribed SubscriptionData


type alias SubscriptionData =
    { auth : String
    , p256dh : String
    , endpoint : String
    }


decodeNewSubscription : JD.Decoder Subscription
decodeNewSubscription =
    JD.map Subscribed
        (JD.map3 SubscriptionData
            (JD.at [ "keys", "auth" ] JD.string)
            (JD.at [ "keys", "p256dh" ] JD.string)
            (JD.at [ "endpoint" ] JD.string)
        )


decodePermissionStatus : JD.Decoder P.PermissionStatus
decodePermissionStatus =
    JD.string
        |> JD.andThen (\s -> JD.succeed (P.permissionStatus s))


decodeClientState : JD.Decoder ClientState
decodeClientState =
    JD.map4 ClientState
        (JD.field "subscription" (JD.nullable JD.bool))
        (JD.field "vapidKey" (JD.nullable JD.string))
        (JD.field "permissionStatus" (JD.nullable decodePermissionStatus))
        (JD.field "login" (JD.nullable decodeLogin))


port onNewSubscriptionInternal : (JD.Value -> msg) -> Sub msg


onNewSubscription : (Result JD.Error Subscription -> msg) -> Sub msg
onNewSubscription msg =
    onNewSubscriptionInternal (JD.decodeValue decodeNewSubscription >> msg)


encodeClientstate : ClientState -> JE.Value
encodeClientstate v =
    JE.object
        [ ( "subscription", maybeNull JE.bool v.subscription )
        , ( "vapidKey", encodeMaybeString v.vapidKey )
        , ( "permissionStatus"
          , Maybe.map P.permissionStatusString v.permissionStatus
                |> encodeMaybeString
          )
        , ( "login", encodeLogin v.login )
        ]


init : () -> ( Model, Cmd Msg )
init _ =
    ( { subscription = Nothing
      , vapidKey = Nothing
      , permissionStatus = Nothing
      , login = Nothing
      , db = Nothing
      , authSaved = False
      }
    , Cmd.batch
        [ getVapidKey ()
        , openDb
        ]
    )


openDb : Cmd Msg
openDb =
    DB.openRequest "elm-pwa-example-db" 1


extendedUpdate : Msg -> Model -> ( Model, Cmd Msg )
extendedUpdate msg model =
    let
        ( newModel, newCmd ) =
            update msg model
    in
    ( newModel
    , Cmd.batch
        [ newCmd
        , updateClients newModel
        ]
    )


getLogin : DB.DB -> Cmd Msg
getLogin db =
    DB.query { db = db, name = "login" }


maybePutLogin : Maybe DB.DB -> Login -> Cmd Msg
maybePutLogin mdb login =
    case mdb of
        Nothing ->
            Cmd.none

        Just db ->
            DB.put { db = db, name = "login" } "key" (encodeLogin (Just login))


checkSubscription : Login -> Cmd msg
checkSubscription login =
    case login of
        LoggedOut ->
            Cmd.none

        LoggedIn loggedIn ->
            authenticatedOpts loggedIn Nothing |> getSubscription


logUpdate :
    (Msg -> Model -> ( Model, Cmd Msg ))
    -> Msg
    -> Model
    -> ( Model, Cmd Msg )
logUpdate f msg model =
    let
        ( newModel, newCmd ) =
            f msg model

        _ =
            Debug.log "SW update" ( msg, newModel, newCmd )
    in
    ( newModel, newCmd )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnDBOpen ( db, resp ) ->
            case resp of
                DB.UpgradeNeeded ->
                    ( model, DB.createObjectStore db "login" )

                DB.Success ->
                    ( { model | db = Just db }, getLogin db )

                _ ->
                    ( model, Cmd.none )

        StoreCreated store ->
            ( model, openDb )

        QueryResult json ->
            let
                result =
                    JD.decodeValue decodeLogin json

                _ =
                    Debug.log "QueryResult JSON " result
            in
            case result of
                Err err ->
                    ( { model | login = Just LoggedOut }, Cmd.none )

                Ok login ->
                    ( { model | login = Just login }, checkSubscription login )

        LoginResult (Err _) ->
            ( model, Cmd.none )

        LoginResult (Ok login) ->
            ( { model | login = Just login }
            , Cmd.batch
                [ maybePutLogin model.db login
                , checkSubscription login
                ]
            )

        OnClientMessage result ->
            case result of
                Err _ ->
                    ( model, Cmd.none )

                Ok cmsg ->
                    case cmsg of
                        Subscribe key ->
                            ( model, SW.subscribePush key )

                        Hello ->
                            ( model, Cmd.none )

                        Login name ->
                            ( model
                            , sendLogin
                                (JE.object
                                    [ ( "name", JE.string name )
                                    ]
                                )
                            )

                        Logout ->
                            ( { model | login = Just LoggedOut }, Cmd.none )

        VapidkeyResult s ->
            ( { model | vapidKey = Just s }, Cmd.none )

        PermissionChange ps ->
            ( { model | permissionStatus = Just ps }, Cmd.none )

        NewSubscription result ->
            case result of
                Err _ ->
                    ( model, Cmd.none )

                Ok subscription ->
                    ( model
                    , maybeSaveSubscription model.login subscription
                    )

        HasSubscription subscription ->
            ( { model | subscription = Just subscription }, Cmd.none )


maybeSaveSubscription : Maybe Login -> Subscription -> Cmd msg
maybeSaveSubscription maybeLogin subscription =
    case maybeLogin of
        Nothing ->
            Cmd.none

        Just login ->
            case login of
                LoggedOut ->
                    Cmd.none

                LoggedIn loggedIn ->
                    case subscription of
                        NoSubscription ->
                            Cmd.none

                        Subscribed data ->
                            authenticatedOpts loggedIn
                                (Just (encodeSubscriptionData data))
                                |> saveSubscription


authenticatedOpts : { token : String, name : String } -> Maybe JE.Value -> JE.Value
authenticatedOpts auth maybePayload =
    ( "auth", JE.string auth.token )
        :: (case maybePayload of
                Nothing ->
                    []

                Just payload ->
                    [ ( "payload", payload ) ]
           )
        |> JE.object


updateClients : Model -> Cmd Msg
updateClients model =
    clientState model
        |> encodeClientstate
        |> SW.postMessage


clientState : Model -> ClientState
clientState model =
    { subscription = model.subscription
    , vapidKey = model.vapidKey
    , permissionStatus = model.permissionStatus
    , login = model.login
    }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ onClientMessage OnClientMessage
        , onVapidkeyResult VapidkeyResult
        , onLoginResult (decodeLoginResult >> LoginResult)
        , P.onPermissionChange PermissionChange
        , DB.openResponse OnDBOpen
        , DB.createObjectStoreResult StoreCreated
        , DB.queryResult QueryResult
        , onNewSubscription NewSubscription
        , getSubscriptionReply HasSubscription
        ]


decodeLoginResult : JD.Value -> Result JD.Error Login
decodeLoginResult =
    JD.decodeValue
        (JD.map2 (\name token -> LoggedIn { name = name, token = token })
            (JD.field "name" JD.string)
            (JD.field "token" JD.string)
        )


sendMessage : ClientMessage -> Cmd msg
sendMessage cm =
    cm |> encodeClientMessage |> SW.postMessage


logout : Cmd msg
logout =
    sendMessage Logout


onClientMessage : (Result JD.Error ClientMessage -> Msg) -> Sub Msg
onClientMessage msg =
    SW.onMessage (JD.decodeValue decodeClientMessage >> msg)


encodeClientMessage : ClientMessage -> JE.Value
encodeClientMessage cm =
    case cm of
        Subscribe key ->
            JE.object
                [ ( "type", JE.string "subscribe" )
                , ( "key", JE.string key )
                ]

        Login name ->
            JE.object
                [ ( "type", JE.string "login" )
                , ( "name", JE.string name )
                ]

        Logout ->
            JE.object
                [ ( "type", JE.string "logout" )
                ]

        Hello ->
            JE.object
                [ ( "type", JE.string "hello" )
                ]


decodeClientMessage : JD.Decoder ClientMessage
decodeClientMessage =
    JD.field "type" JD.string
        |> JD.andThen
            (\typ ->
                case typ of
                    "subscribe" ->
                        JD.field "key" JD.string
                            |> JD.andThen (\key -> JD.succeed (Subscribe key))

                    "login" ->
                        JD.field "name" JD.string
                            |> JD.andThen (\name -> JD.succeed (Login name))

                    "hello" ->
                        JD.succeed Hello

                    "logout" ->
                        JD.succeed Logout

                    _ ->
                        JD.fail <| "unknown message: " ++ typ
            )
