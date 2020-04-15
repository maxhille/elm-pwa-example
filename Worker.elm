module Worker exposing (main)

import IndexedDB
import Json.Decode
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
    | SWClientMessage (Result SW.Error SW.ClientMessage)
    | SWFetchResult SW.FetchResult
    | PermissionChange P.PermissionStatus


init : () -> ( Model, Cmd Msg )
init flags =
    ( initialModel, IndexedDB.open "elm-pwa-example-db" )


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
                Err s ->
                    ( model, Cmd.none )

                Ok subscription ->
                    ( { model | subscription = subscription }, Cmd.none )

        SWClientMessage result ->
            case result of
                Ok cmsg ->
                    case cmsg of
                        SW.Subscribe ->
                            ( model, SW.fetch )

                        SW.Hello ->
                            ( model, Cmd.none )

                Err err ->
                    ( model, Cmd.none )

        SWFetchResult result ->
            ( model, Cmd.none )

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
        , SW.onClientMessage SWClientMessage
        , SW.onFetchResult SWFetchResult
        , P.onPermissionChange PermissionChange
        ]
