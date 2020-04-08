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
    | SWSubscription SW.Subscription
    | SWMessage SW.Message
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

        SWSubscription subscription ->
            ( { model | subscription = subscription }, updateClients model )

        SWMessage swmsg ->
            case swmsg of
                SW.Subscribe ->
                    ( model, SW.fetch )

                _ ->
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
        [ SW.subscriptionState SWSubscription
        , SW.onMessage SWMessage
        , SW.onFetchResult SWFetchResult
        ]
