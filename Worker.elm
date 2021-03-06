port module Worker exposing
    ( ClientMessage(..)
    , ClientState
    , Login(..)
    , Post
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
import Task
import Time
import UUID exposing (UUID)


port getVapidKey : () -> Cmd msg


port onVapidkeyResult : (String -> msg) -> Sub msg


port sendLogin : JE.Value -> Cmd msg


port uploadSubscription : JE.Value -> Cmd msg


port uploadPost : JE.Value -> Cmd msg


port uploadPostReply : (JE.Value -> msg) -> Sub msg


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


type alias Post =
    { id : UUID
    , user : User
    , time : Time.Posix
    , text : String
    , status : PostStatus
    }


type alias Model =
    { subscription : Maybe Bool
    , vapidKey : Maybe String
    , permissionStatus : Maybe P.PermissionStatus
    , login : Maybe Login
    , db : Maybe DB.DB
    , authSaved : Bool
    , posts : List Post
    , uuidNamespace : UUID
    , errors : List String
    }


type Msg
    = OnDBOpen ( DB.DB, DB.OpenResponse )
    | OnClientMessage (Result JD.Error ClientMessage)
    | VapidkeyResult String
    | PermissionChange P.PermissionStatus
    | StoreCreated (Result JD.Error DB.ObjectStore)
    | QueryError String
    | LoginResult (Result JD.Error Login)
    | NewSubscription (Result JD.Error Subscription)
    | HasSubscription Bool
    | NewPost Post
    | Sync String
    | OnPutResult (Result JD.Error DB.PutResult)
    | LoginQueryResult JD.Value
    | PostsQueryResult JD.Value
    | UploadPostResult (Result PostError UUID.UUID)


type alias PostError =
    String


type PostStatus
    = Sent
    | Pending
    | Failed


type Login
    = LoggedOut
    | LoggedIn User Token


type alias Token =
    String


type alias User =
    { id : String
    , name : String
    }


type ClientMessage
    = Subscribe String
    | Hello
    | Login String
    | Logout
    | SubmitPost String


type alias ClientState =
    { subscription : Maybe Bool
    , vapidKey : Maybe String
    , permissionStatus : Maybe P.PermissionStatus
    , login : Maybe Login
    , posts : List Post
    , swErrors : List String
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
                LoggedIn user token ->
                    JE.object
                        [ ( "type", JE.string "logged-in" )
                        , ( "user", encodeUser user )
                        , ( "token", JE.string token )
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
                        JD.map2 LoggedIn
                            (JD.field "user" userDecoder)
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
    JD.map6 ClientState
        (JD.field "subscription" (JD.nullable JD.bool))
        (JD.field "vapidKey" (JD.nullable JD.string))
        (JD.field "permissionStatus" (JD.nullable decodePermissionStatus))
        (JD.field "login" (JD.nullable decodeLogin))
        (JD.field "posts" (JD.list postDecoder))
        (JD.field "swErrors" (JD.list JD.string))


port onNewSubscriptionInternal : (JD.Value -> msg) -> Sub msg


onNewSubscription : (Result JD.Error Subscription -> msg) -> Sub msg
onNewSubscription msg =
    onNewSubscriptionInternal (JD.decodeValue decodeNewSubscription >> msg)


encodeClientstate : ClientState -> JE.Value
encodeClientstate cs =
    JE.object
        [ ( "subscription", maybeNull JE.bool cs.subscription )
        , ( "vapidKey", encodeMaybeString cs.vapidKey )
        , ( "permissionStatus"
          , Maybe.map P.permissionStatusString cs.permissionStatus
                |> encodeMaybeString
          )
        , ( "login", encodeLogin cs.login )
        , ( "posts", JE.list encodePost cs.posts )
        , ( "swErrors", JE.list JE.string cs.swErrors )
        ]


encodePost : Post -> JE.Value
encodePost post =
    JE.object
        [ ( "user", encodeUser post.user )
        , ( "id", JE.string (UUID.toString post.id) )
        , ( "time", JE.int (Time.posixToMillis post.time) )
        , ( "text", JE.string post.text )
        , ( "status", encodeStatus post.status )
        ]


encodeStatus : PostStatus -> JE.Value
encodeStatus status =
    case status of
        Pending ->
            JE.string "pending"

        Sent ->
            JE.string "sent"

        Failed ->
            JE.string "failed"


postDecoder : JD.Decoder Post
postDecoder =
    JD.map5 Post
        (JD.field "id" uuidDecoder)
        (JD.field "user" userDecoder)
        (JD.field "time" (JD.map Time.millisToPosix JD.int))
        (JD.field "text" JD.string)
        (JD.field "status" postStatusDecoder)


postStatusDecoder : JD.Decoder PostStatus
postStatusDecoder =
    JD.string
        |> JD.andThen
            (\s ->
                case s of
                    "pending" ->
                        JD.succeed Pending

                    "sent" ->
                        JD.succeed Sent

                    "failed" ->
                        JD.succeed Failed

                    _ ->
                        JD.fail ("could not decode PostStatus: " ++ s)
            )


uuidDecoder : JD.Decoder UUID
uuidDecoder =
    JD.string
        |> JD.andThen
            (\s ->
                case UUID.fromString s of
                    Err _ ->
                        JD.fail ("could not parse UUID from " ++ s)

                    Ok uuid ->
                        JD.succeed uuid
            )


encodeUser : User -> JE.Value
encodeUser user =
    JE.object
        [ ( "id", JE.string user.id )
        , ( "name", JE.string user.name )
        ]


init : () -> ( Model, Cmd Msg )
init _ =
    ( { subscription = Nothing
      , vapidKey = Nothing
      , permissionStatus = Nothing
      , login = Nothing
      , db = Nothing
      , authSaved = False
      , posts = []
      , errors = []
      , uuidNamespace =
            UUID.forName "http://github.com/maxhille" UUID.urlNamespace
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


queryLogin : DB.DB -> Cmd Msg
queryLogin db =
    DB.get { db = db, name = "login" } (DB.GetKey "key")


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

        LoggedIn _ token ->
            authenticatedOpts token Nothing |> getSubscription


logUpdate :
    (Msg -> Model -> ( Model, Cmd Msg ))
    -> Msg
    -> Model
    -> ( Model, Cmd Msg )
logUpdate f msg model =
    let
        ( newModel, newCmd ) =
            f msg model

        {-
           _ =
               Debug.log "SW update" ( msg, newModel, newCmd )
        -}
    in
    ( newModel, newCmd )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnDBOpen ( db, resp ) ->
            case resp of
                DB.UpgradeNeeded ->
                    ( model
                    , Cmd.batch
                        [ DB.createObjectStore db "login"
                        , DB.createObjectStore db "posts"
                        ]
                    )

                DB.Success ->
                    ( { model | db = Just db }
                    , Cmd.batch
                        [ queryLogin db
                        , queryPosts db
                        ]
                    )

                _ ->
                    ( model |> addError "unhandled DB event", Cmd.none )

        StoreCreated _ ->
            ( model, openDb )

        QueryError err ->
            ( model |> addError err, Cmd.none )

        PostsQueryResult json ->
            let
                result =
                    JD.decodeValue postsDecoder json
            in
            case result of
                Err err ->
                    ( model |> addError (JD.errorToString err), Cmd.none )

                Ok posts ->
                    ( { model | posts = posts }, Cmd.none )

        LoginQueryResult json ->
            let
                result =
                    JD.decodeValue decodeLogin json
            in
            case result of
                Err err ->
                    ( { model
                        | login = Just LoggedOut
                      }
                        |> addError (JD.errorToString err)
                    , Cmd.none
                    )

                Ok login ->
                    ( { model | login = Just login }, checkSubscription login )

        LoginResult (Err err) ->
            ( model |> addError (JD.errorToString err), Cmd.none )

        LoginResult (Ok login) ->
            ( { model | login = Just login }
            , Cmd.batch
                [ maybePutLogin model.db login
                , checkSubscription login
                ]
            )

        OnClientMessage result ->
            case result of
                Err err ->
                    ( model |> addError (JD.errorToString err), Cmd.none )

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

                        SubmitPost text ->
                            ( model, newPost model text )

                        Logout ->
                            ( { model | login = Just LoggedOut }, Cmd.none )

        VapidkeyResult s ->
            ( { model | vapidKey = Just s }, Cmd.none )

        PermissionChange ps ->
            ( { model | permissionStatus = Just ps }, Cmd.none )

        NewSubscription result ->
            case result of
                Err err ->
                    ( model |> addError (JD.errorToString err), Cmd.none )

                Ok subscription ->
                    ( model
                    , maybeSaveSubscription model.login subscription
                    )

        HasSubscription subscription ->
            ( { model | subscription = Just subscription }, Cmd.none )

        Sync _ ->
            -- TODO do something here?
            ( model, Cmd.none )

        NewPost post ->
            ( model
            , Cmd.batch
                [ savePost model.db post
                , maybeUploadPost model.login post
                ]
            )

        OnPutResult result ->
            case result of
                Err err ->
                    ( model |> addError (JD.errorToString err), Cmd.none )

                Ok putResult ->
                    ( model, queryPosts putResult.store.db )

        UploadPostResult result ->
            case result of
                Err err ->
                    ( model |> addError err, Cmd.none )

                Ok ok ->
                    -- TODO update status in db
                    ( model, Cmd.none )


addError : String -> Model -> Model
addError str model =
    { model | errors = List.append model.errors [ str ] }


queryPosts : DB.DB -> Cmd Msg
queryPosts db =
    DB.get { db = db, name = "posts" } DB.GetAll


savePost : Maybe DB.DB -> Post -> Cmd Msg
savePost maybeDb post =
    case maybeDb of
        Nothing ->
            Cmd.none

        Just db ->
            DB.put { db = db, name = "posts" }
                (UUID.toString post.id)
                (encodePost post)


maybeUploadPost : Maybe Login -> Post -> Cmd Msg
maybeUploadPost maybeLogin post =
    case maybeLogin of
        Nothing ->
            Cmd.none

        Just login ->
            case login of
                LoggedOut ->
                    Cmd.none

                LoggedIn _ token ->
                    authenticatedOpts token
                        (Just (encodePost post))
                        |> uploadPost


newPost : Model -> String -> Cmd Msg
newPost model text =
    case model.login of
        Nothing ->
            Cmd.none

        Just login ->
            case login of
                LoggedOut ->
                    Cmd.none

                LoggedIn user _ ->
                    Task.perform
                        (\time ->
                            NewPost
                                { id = uuidForTime model time
                                , user = user
                                , text = text
                                , time = time
                                , status = Pending
                                }
                        )
                        Time.now


uuidForTime : Model -> Time.Posix -> UUID
uuidForTime model time =
    UUID.forName (String.fromInt (Time.posixToMillis time)) model.uuidNamespace


maybeSaveSubscription : Maybe Login -> Subscription -> Cmd msg
maybeSaveSubscription maybeLogin subscription =
    case maybeLogin of
        Nothing ->
            Cmd.none

        Just login ->
            case login of
                LoggedOut ->
                    Cmd.none

                LoggedIn _ token ->
                    case subscription of
                        NoSubscription ->
                            Cmd.none

                        Subscribed data ->
                            authenticatedOpts token
                                (Just (encodeSubscriptionData data))
                                |> uploadSubscription


authenticatedOpts : Token -> Maybe JE.Value -> JE.Value
authenticatedOpts token maybePayload =
    ( "auth", JE.string token )
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
    , posts = model.posts
    , swErrors = model.errors
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
        , onQueryResult
        , onNewSubscription NewSubscription
        , getSubscriptionReply HasSubscription
        , SW.onSync Sync
        , DB.putResult OnPutResult
        , onUploadPostReply UploadPostResult
        ]


onUploadPostReply : (Result PostError UUID.UUID -> msg) -> Sub msg
onUploadPostReply msg =
    uploadPostReply (JD.decodeValue uploadPostReplyDecoder >> toPostError >> msg)


toPostError : Result JD.Error a -> Result PostError a
toPostError result =
    case result of
        Ok a ->
            Ok a

        Err err ->
            Err <| "json decoder error: " ++ JD.errorToString err


uploadPostReplyDecoder : JD.Decoder UUID.UUID
uploadPostReplyDecoder =
    JD.field "status" JD.int
        |> JD.andThen
            (\status ->
                case status of
                    201 ->
                        JD.field "id" uuidDecoder

                    _ ->
                        JD.fail <| "unexpected response: " ++ String.fromInt status
            )


onQueryResult : Sub Msg
onQueryResult =
    DB.getResult
        (\qr ->
            case qr of
                Err err ->
                    QueryError (JD.errorToString err)

                Ok ( store, _, data ) ->
                    case store.name of
                        "login" ->
                            LoginQueryResult data

                        "posts" ->
                            PostsQueryResult data

                        _ ->
                            QueryError
                                ("result not handled for store" ++ store.name)
        )


decodeLoginResult : JD.Value -> Result JD.Error Login
decodeLoginResult =
    JD.decodeValue
        (JD.map2 LoggedIn
            (JD.field "user" userDecoder)
            (JD.field "token" JD.string)
        )


postsDecoder : JD.Decoder (List Post)
postsDecoder =
    JD.list
        (JD.map5
            (\id user time text status ->
                { id = id
                , user = user
                , time = Time.millisToPosix time
                , text = text
                , status = status
                }
            )
            (JD.field "id" uuidDecoder)
            (JD.field "user" userDecoder)
            (JD.field "time" JD.int)
            (JD.field "text" JD.string)
            (JD.field "status" postStatusDecoder)
        )


userDecoder : JD.Decoder User
userDecoder =
    JD.map2 User
        (JD.field "id" JD.string)
        (JD.field "name" JD.string)


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

        SubmitPost text ->
            JE.object
                [ ( "type", JE.string "post" )
                , ( "text", JE.string text )
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

                    "post" ->
                        JD.field "text" JD.string
                            |> JD.andThen (\text -> JD.succeed (SubmitPost text))

                    "hello" ->
                        JD.succeed Hello

                    "logout" ->
                        JD.succeed Logout

                    _ ->
                        JD.fail <| "unknown message type: " ++ typ
            )
