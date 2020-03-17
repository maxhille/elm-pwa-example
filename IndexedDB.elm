port module IndexedDB exposing (open, subscriptions)


type DBState
    = Uninitialized
    | Initialized


port initialized : (() -> msg) -> Sub msg


port initialize : String -> Cmd msg



-- port cache : E.Value -> Cmd msg
-- open : String ->
-- open dbName =


open string =
    initialize string


subscriptions : msg -> Sub msg
subscriptions onInitialized =
    initialized (\_ -> onInitialized)
