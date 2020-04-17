module Worker exposing
    ( ClientMessage(..)
    , main
    , sendMessage
    )

import IndexedDB as DB
import Json.Decode as JD
import Json.Encode as JE
import Permissions as P
import Platform
import ServiceWorker as SW


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
    }


type Msg
    = OnDBOpen ( DB.DB, DB.OpenResponse )
    | OnClientMessage (Result JD.Error ClientMessage)
    | SWFetchResult SW.FetchResult
    | PermissionChange P.PermissionStatus
    | StoreCreated (Result JD.Error DB.ObjectStore)


type ClientMessage
    = Subscribe String
    | Hello


init : () -> ( Model, Cmd Msg )
init _ =
    ( { subscription = SW.NoSubscription
      , vapidKey = Nothing
      , permissionStatus = Nothing
      }
    , Cmd.batch
        [ SW.fetch
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

        SWFetchResult vapidKey ->
            ( { model | vapidKey = Just vapidKey }, Cmd.none )

        PermissionChange ps ->
            ( { model | permissionStatus = Just ps }, Cmd.none )


updateClients : Model -> Cmd Msg
updateClients model =
    clientState model |> SW.updateClients


getAuth : DB.ObjectStore -> Cmd Msg
getAuth =
    DB.query


clientState : Model -> SW.ClientState
clientState model =
    { subscription = model.subscription
    , vapidKey = model.vapidKey
    , permissionStatus = model.permissionStatus
    }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ onClientMessage OnClientMessage
        , SW.onFetchResult SWFetchResult
        , P.onPermissionChange PermissionChange
        , DB.openResponse OnDBOpen
        , DB.createObjectStoreResult StoreCreated
        ]


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

                    "hello" ->
                        JD.succeed Hello

                    _ ->
                        JD.fail <| "unknown message: " ++ typ
            )
