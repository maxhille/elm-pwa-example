port module ServiceWorker exposing
    ( Availability(..)
    , Registration(..)
    , checkAvailability
    , getAvailability
    , register
    )


type Availability
    = Unknown
    | Available
    | NotAvailable


type Registration
    = NotRegistered
    | Registered
    | RegistrationError


register : Cmd msg
register =
    registrationRequest ()


port availabilityResponse : (Bool -> msg) -> Sub msg


port availabilityRequest : () -> Cmd msg


port registrationRequest : () -> Cmd msg


checkAvailability : Cmd msg
checkAvailability =
    availabilityRequest ()


getAvailability : (Availability -> msg) -> Sub msg
getAvailability f =
    availabilityResponse (availabilityFromBool >> f)


availabilityFromBool : Bool -> Availability
availabilityFromBool b =
    if b then
        Available

    else
        NotAvailable
