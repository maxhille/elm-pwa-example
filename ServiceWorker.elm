port module ServiceWorker exposing
    ( Availability
    , checkAvailability
    , getAvailability
    )


type Availability
    = Unknown
    | Available
    | NotAvailable


port availabilityResponse : (Bool -> msg) -> Sub msg


port availabilityRequest : () -> Cmd msg


checkAvailability : Cmd msg
checkAvailability =
    availabilityRequest ()


getAvailability : (Availability -> msg) -> Sub msg
getAvailability f =
    -- availabilityResponse (availabilityFromBool >> f)
    (availabilityFromBool >> f)
        |> availabilityResponse


availabilityFromBool : Bool -> Availability
availabilityFromBool b =
    if b then
        Available

    else
        NotAvailable
