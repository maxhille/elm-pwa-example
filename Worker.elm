port module Worker exposing
    ( Auth(..)
    , ClientMessage(..)
    , ClientState
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


port login : JE.Value -> Cmd msg


port onLoginResult : (JD.Value -> msg) -> Sub msg


main =
    Platform.worker
        { init = init
        , subscriptions = subscriptions
        , update = logUpdate extendedUpdate
        }


type alias Model =
    { subscription : SW.Subscription
    , vapidKey : Maybe String
    , permissionStatus : Maybe P.PermissionStatus
    , auth : Maybe Auth
    }


type Msg
    = OnDBOpen ( DB.DB, DB.OpenResponse )
    | OnClientMessage (Result JD.Error ClientMessage)
    | VapidkeyResult String
    | PermissionChange P.PermissionStatus
    | StoreCreated (Result JD.Error DB.ObjectStore)
    | QueryResult DB.QueryResult
    | LoginResult (Result JD.Error Auth)


type Auth
    = LoggedOut
    | LoggedIn
        { name : String
        , token : String
        }


type ClientMessage
    = Subscribe String
    | Hello
    | Login String


type alias ClientState =
    { subscription : SW.Subscription
    , vapidKey : Maybe String
    , permissionStatus : Maybe P.PermissionStatus
    , auth : Maybe Auth
    }


onClientUpdate : (Result JD.Error ClientState -> msg) -> Sub msg
onClientUpdate msg =
    SW.onMessage
        (JD.decodeValue decodeClientState >> msg)


encodeMaybeString : Maybe String -> JE.Value
encodeMaybeString ms =
    case ms of
        Nothing ->
            JE.null

        Just s ->
            JE.string s


encodeSubscription : SW.Subscription -> JE.Value
encodeSubscription subscription =
    case subscription of
        SW.NoSubscription ->
            JE.object [ ( "type", JE.string "none" ) ]

        SW.Subscribed data ->
            JE.object
                [ ( "type", JE.string "subscribed" )
                , ( "data"
                  , JE.object
                        [ ( "auth", JE.string data.auth )
                        , ( "p256dh", JE.string data.p256dh )
                        , ( "endpoint", JE.string data.endpoint )
                        ]
                  )
                ]


encodeAuth : Maybe Auth -> JE.Value
encodeAuth maybe =
    case maybe of
        Nothing ->
            JE.null

        Just auth ->
            case auth of
                LoggedIn _ ->
                    JE.string "logged-in"

                LoggedOut ->
                    JE.string "logged-out"


subscriptionDataDecoder : JD.Decoder SW.SubscriptionData
subscriptionDataDecoder =
    JD.map3 SW.SubscriptionData
        (JD.at [ "auth" ] JD.string)
        (JD.at [ "p256dh" ] JD.string)
        (JD.at [ "endpoint" ] JD.string)


decodePermissionStatus : JD.Decoder P.PermissionStatus
decodePermissionStatus =
    JD.string
        |> JD.andThen (\s -> JD.succeed (P.permissionStatus s))


decodeClientState : JD.Decoder ClientState
decodeClientState =
    JD.map4 ClientState
        (JD.at [ "subscription" ] SW.decodeSubscription)
        (JD.at [ "vapidKey" ] (JD.nullable JD.string))
        (JD.at [ "permissionStatus" ] (JD.nullable decodePermissionStatus))
        (JD.at [ "auth" ] (JD.nullable decodeAuth))


decodeAuth : JD.Decoder Auth
decodeAuth =
    JD.succeed LoggedOut


encodeClientstate : ClientState -> JE.Value
encodeClientstate v =
    JE.object
        [ ( "subscription", encodeSubscription v.subscription )
        , ( "vapidKey", encodeMaybeString v.vapidKey )
        , ( "permissionStatus"
          , Maybe.map P.permissionStatusString v.permissionStatus
                |> encodeMaybeString
          )
        , ( "auth", encodeAuth v.auth )
        ]


init : () -> ( Model, Cmd Msg )
init _ =
    ( { subscription = SW.NoSubscription
      , vapidKey = Nothing
      , permissionStatus = Nothing
      , auth = Just LoggedOut
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
    ( newModel, Cmd.batch [ newCmd, updateClients newModel ] )


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
                    ( model, DB.createObjectStore db "auth" )

                DB.Success ->
                    ( model, DB.query { db = db, name = "auth" } )

                _ ->
                    ( model, Cmd.none )

        StoreCreated store ->
            ( model, openDb )

        QueryResult json ->
            ( model, Cmd.none )

        LoginResult (Err _) ->
            ( model, Cmd.none )

        LoginResult (Ok auth) ->
            {- TODO write auth to DB, do same stuff as above -}
            ( model, Cmd.none )

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
                            , login
                                (JE.object
                                    [ ( "name", JE.string name )
                                    ]
                                )
                            )

        VapidkeyResult s ->
            ( { model | vapidKey = Just s }, Cmd.none )

        PermissionChange ps ->
            ( { model | permissionStatus = Just ps }, Cmd.none )


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
    , auth = model.auth
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
        ]


decodeLoginResult : JD.Value -> Result JD.Error Auth
decodeLoginResult _ =
    Ok LoggedOut


sendMessage : ClientMessage -> Cmd msg
sendMessage cm =
    cm |> encodeClientMessage |> SW.postMessage


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

                    _ ->
                        JD.fail <| "unknown message: " ++ typ
            )
