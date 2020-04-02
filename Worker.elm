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
    { text : String }


type Msg
    = TextChanged String
    | DBInitialized
    | SWSubscription (Result Json.Decode.Error SW.Subscription)


init : () -> ( Model, Cmd Msg )
init flags =
    ( initialModel, IndexedDB.open "elm-pwa-example-db" )


initialModel : Model
initialModel =
    { text = "" }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        TextChanged newText ->
            ( { model | text = newText }, Cmd.none )

        DBInitialized ->
            ( model, Cmd.none )

        SWSubscription result ->
            let
                newModel =
                    model

                cmd =
                    case result of
                        Err _ ->
                            Cmd.none

                        Ok maybe ->
                            case maybe of
                                Nothing ->
                                    SW.sendBroadcast False

                                Just _ ->
                                    SW.sendBroadcast True
            in
            ( newModel, cmd )


subscriptions : Model -> Sub Msg
subscriptions model =
    SW.subscriptionState SWSubscription
