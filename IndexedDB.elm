port module IndexedDB exposing
    ( DB
    , GetResult
    , ObjectStore
    , OpenResponse(..)
    , PutResult
    , Query(..)
    , createObjectStore
    , createObjectStoreResult
    , get
    , getResult
    , openRequest
    , openResponse
    , put
    , putResult
    )

import Json.Decode as JD
import Json.Encode as JE


type OpenResponse
    = Success
    | UpgradeNeeded
    | Error


type alias GetResult =
    ( ObjectStore, Query, JD.Value )


type alias DB =
    String


type Query
    = GetAll
    | GetKey String


type alias ObjectStore =
    { db : DB
    , name : String
    }


type alias PutResult =
    { store : ObjectStore
    , key : Maybe String
    }


port putInternal : JE.Value -> Cmd msg


port putResultInternal : (JD.Value -> msg) -> Sub msg


putResult : (Result JD.Error PutResult -> msg) -> Sub msg
putResult msg =
    putResultInternal (JD.decodeValue decodePutResult >> msg)


decodePutResult : JD.Decoder PutResult
decodePutResult =
    JD.map2 PutResult
        (JD.field "store" objectStoreDecoder)
        (JD.field "key" (JD.nullable JD.string))


put : ObjectStore -> String -> JE.Value -> Cmd msg
put os key data =
    JE.object
        [ ( "db", JE.string os.db )
        , ( "name", JE.string os.name )
        , ( "data", data )
        , ( "key", JE.string key )
        ]
        |> putInternal


port getInternal : JE.Value -> Cmd msg


get : ObjectStore -> Query -> Cmd msg
get store query =
    List.concat
        [ [ ( "db", JE.string store.db )
          , ( "name", JE.string store.name )
          ]
        , case query of
            GetKey key ->
                [ ( "key", JE.string key ) ]

            GetAll ->
                [ ( "key", JE.null ) ]
        ]
        |> JE.object
        |> getInternal


port getResultInternal : (JD.Value -> msg) -> Sub msg


getResult : (Result JD.Error GetResult -> msg) -> Sub msg
getResult msg =
    getResultInternal (JD.decodeValue resultDecoder >> msg)


resultDecoder : JD.Decoder GetResult
resultDecoder =
    JD.map3
        (\store query data -> ( store, query, data ))
        (JD.field "store" objectStoreDecoder)
        (JD.field "query" queryDecoder)
        (JD.field "data" JD.value)


queryDecoder : JD.Decoder Query
queryDecoder =
    JD.nullable JD.string
        |> JD.andThen
            (\maybe ->
                case maybe of
                    Nothing ->
                        GetAll |> JD.succeed

                    Just key ->
                        GetKey key |> JD.succeed
            )


port openResponseInternal : (JD.Value -> msg) -> Sub msg


port openRequestInternal : JE.Value -> Cmd msg


port createObjectStoreInternal : JE.Value -> Cmd msg


port createObjectStoreResultInternal : (JD.Value -> msg) -> Sub msg


createObjectStoreResult : (Result JD.Error ObjectStore -> msg) -> Sub msg
createObjectStoreResult msg =
    createObjectStoreResultInternal (JD.decodeValue objectStoreDecoder >> msg)


objectStoreDecoder : JD.Decoder ObjectStore
objectStoreDecoder =
    JD.map2
        (\db name -> { db = db, name = name })
        (JD.field "db" JD.string)
        (JD.field "name" JD.string)


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
