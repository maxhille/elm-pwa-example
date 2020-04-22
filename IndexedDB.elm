port module IndexedDB exposing
    ( DB
    , ObjectStore
    , OpenResponse(..)
    , QueryResult
    , createObjectStore
    , createObjectStoreResult
    , openRequest
    , openResponse
    , put
    , query
    , queryResult
    )

import Json.Decode as JD
import Json.Encode as JE


type OpenResponse
    = Success
    | UpgradeNeeded
    | Error


type alias QueryResult =
    JD.Value


type alias DB =
    String


type alias ObjectStore =
    { db : DB
    , name : String
    }


port putInternal : JE.Value -> Cmd msg


put : ObjectStore -> String -> JE.Value -> Cmd msg
put os key data =
    JE.object
        [ ( "db", JE.string os.db )
        , ( "name", JE.string os.name )
        , ( "data", data )
        , ( "key", JE.string key )
        ]
        |> putInternal


port queryInternal : JE.Value -> Cmd msg


query : ObjectStore -> Cmd msg
query store =
    JE.object
        [ ( "db", JE.string store.db )
        , ( "name", JE.string store.name )
        ]
        |> queryInternal


port queryResultInternal : (JD.Value -> msg) -> Sub msg


queryResult : (QueryResult -> msg) -> Sub msg
queryResult =
    queryResultInternal


port openResponseInternal : (JD.Value -> msg) -> Sub msg


port openRequestInternal : JE.Value -> Cmd msg


port createObjectStoreInternal : JE.Value -> Cmd msg


port createObjectStoreResultInternal : (JD.Value -> msg) -> Sub msg


createObjectStoreResult : (Result JD.Error ObjectStore -> msg) -> Sub msg
createObjectStoreResult msg =
    createObjectStoreResultInternal (decodeObjectStore >> msg)


decodeObjectStore : JD.Value -> Result JD.Error ObjectStore
decodeObjectStore =
    JD.map2
        (\db name -> { db = db, name = name })
        (JD.field "db" JD.string)
        (JD.field "name" JD.string)
        |> JD.decodeValue


createObjectStore : DB -> String -> Cmd msg
createObjectStore db name =
    JE.object
        [ ( "db", JE.string db )
        , ( "name", JE.string name )
        ]
        |> createObjectStoreInternal


openRequest : DB -> Int -> Cmd msg
openRequest name version =
    JE.object
        [ ( "name", JE.string name )
        , ( "version", JE.int version )
        ]
        |> openRequestInternal


openResponse : (( DB, OpenResponse ) -> msg) -> Sub msg
openResponse msg =
    openResponseInternal (decodeOpenResponse >> msg)


decodeOpenResponse : JD.Value -> ( DB, OpenResponse )
decodeOpenResponse v =
    let
        result : Result JD.Error ( DB, OpenResponse )
        result =
            JD.decodeValue
                (JD.map2
                    Tuple.pair
                    (JD.at [ "name" ] JD.string)
                    (JD.at [ "result" ] decodeResult)
                )
                v
    in
    case result of
        Err _ ->
            ( "could not get name", Error )

        Ok ( db, response ) ->
            ( db, response )


decodeResult : JD.Decoder OpenResponse
decodeResult =
    JD.string
        |> JD.andThen
            (\s ->
                case s of
                    "success" ->
                        JD.succeed Success

                    "error" ->
                        JD.succeed Error

                    "upgrade-needed" ->
                        JD.succeed UpgradeNeeded

                    _ ->
                        JD.fail ("unknown response: " ++ s)
            )
