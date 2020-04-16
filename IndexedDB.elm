port module IndexedDB exposing
    ( DB
    , OpenResponse(..)
    , createObjectStore
    , openRequest
    , openResponse
    )

import Json.Decode as JD
import Json.Encode as JE


type OpenResponse
    = Success
    | UpgradeNeeded
    | Error


type alias DB =
    String


port openResponseInternal : (JD.Value -> msg) -> Sub msg


port openRequestInternal : JE.Value -> Cmd msg


port createObjectStoreInternal : () -> Cmd msg


createObjectStore : () -> Cmd msg
createObjectStore =
    createObjectStoreInternal


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
