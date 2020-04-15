module Worker exposing
    ( ClientMessage(..)
    , main
    , sendMessage
    )

import IndexedDB
import Json.Decode as JD
import Json.Encode as JE
import Permissions as P
import Platform
import ServiceWorker as SW


main =
    Platform.worker
        { init = init
        , subscriptions = subscriptions
        , update = extendedUpdate
        }


type alias Model =
    { subscription : SW.Subscription
    , vapidKey : Maybe String
    , permissionStatus : Maybe P.PermissionStatus
    }


type Msg
    = DBInitialized
    | SWSubscription (Result SW.Error SW.Subscription)
    | OnClientMessage (Result JD.Error ClientMessage)
    | SWFetchResult SW.FetchResult
    | PermissionChange P.PermissionStatus


type ClientMessage
    = Subscribe String
    | Hello


init : () -> ( Model, Cmd Msg )
init flags =
    ( initialModel
    , Cmd.batch
        [ SW.fetch
        , IndexedDB.open "elm-pwa-example-db"
        ]
    )


initialModel : Model
initialModel =
    { subscription = SW.NoSubscription
    , vapidKey = Nothing
    , permissionStatus = Nothing
    }


extendedUpdate : Msg -> Model -> ( Model, Cmd Msg )
extendedUpdate msg model =
    let
        ( newModel, newCmd ) =
            update msg model
    in
    ( newModel, Cmd.batch [ newCmd, updateClients newModel ] )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        DBInitialized ->
            ( model, Cmd.none )

        SWSubscription result ->
            case result of
                Err _ ->
                    ( model, Cmd.none )

                Ok subscription ->
                    ( { model | subscription = subscription }, Cmd.none )

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


clientState : Model -> SW.ClientState
clientState model =
    { subscription = model.subscription
    , vapidKey = model.vapidKey
    , permissionStatus = model.permissionStatus
    }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ SW.onSubscriptionState SWSubscription
        , onClientMessage OnClientMessage
        , SW.onFetchResult SWFetchResult
        , P.onPermissionChange PermissionChange
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
