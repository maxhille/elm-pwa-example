module Worker exposing (main)

import IndexedDB
import Platform


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


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none
