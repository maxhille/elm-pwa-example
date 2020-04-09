module Worker exposing (main)

import IndexedDB
import Json.Decode
import Platform
import ServiceWorker as SW


main =
    Platform.worker
        { init = init
        , subscriptions = subscriptions
        , update = update
        }


type alias Model =
    { subscription : SW.Subscription
    , vapidKey : Maybe String
    }


type Msg
    = DBInitialized
    | SWSubscription (Result SW.Error SW.Subscription)
    | SWClientMessage (Result SW.Error SW.ClientMessage)
    | SWFetchResult SW.FetchResult


init : () -> ( Model, Cmd Msg )
init flags =
    ( initialModel, IndexedDB.open "elm-pwa-example-db" )


initialModel : Model
initialModel =
    { subscription = SW.NoSubscription
    , vapidKey = Nothing
    }


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
                    ( { model | subscription = subscription }, updateClients model )

        SWClientMessage result ->
            case result of
                Ok cmsg ->
                    case cmsg of
                        SW.Subscribe ->
                            ( model, SW.fetch )

                Err _ ->
                    ( model, Cmd.none )

        SWFetchResult result ->
            ( { model | vapidKey = Just result }, updateClients model )


updateClients : Model -> Cmd Msg
updateClients model =
    clientState model |> SW.updateClients


clientState : Model -> SW.ClientState
clientState model =
    { subscription = model.subscription
    , vapidKey = model.vapidKey
    }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ SW.onSubscriptionState SWSubscription
        , SW.onClientMessage SWClientMessage
        , SW.onFetchResult SWFetchResult
        ]
