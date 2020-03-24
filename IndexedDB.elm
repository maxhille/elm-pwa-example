port module IndexedDB exposing (open, subscriptions)


type DBState
    = Uninitialized
    | Initialized


port idxdbInitResponse : (() -> msg) -> Sub msg


port idxdbInitRequest : String -> Cmd msg


open string =
    idxdbInitRequest string


subscriptions : msg -> Sub msg
subscriptions onInitialized =
    idxdbInitResponse (\_ -> onInitialized)
