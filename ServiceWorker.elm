port module ServiceWorker exposing
    ( Availability(..)
    , Registration(..)
    , checkAvailability
    , getAvailability
    , getRegistration
    , postMessage
    , register
    )


type Availability
    = Unknown
    | Available
    | NotAvailable


type Registration
    = RegistrationUnknown
    | RegistrationSuccess
    | RegistrationError


register : Cmd msg
register =
    registrationRequest ()


postMessage : Cmd msg
postMessage =
    postMessageInternal ()


getRegistration : (Registration -> msg) -> Sub msg
getRegistration f =
    registrationResponse (registrationFromString >> f)


registrationFromString : String -> Registration
registrationFromString s =
    if s == "success" then
        RegistrationSuccess

    else
        RegistrationError


port availabilityResponse : (Bool -> msg) -> Sub msg


port availabilityRequest : () -> Cmd msg


port postMessageInternal : () -> Cmd msg


port registrationRequest : () -> Cmd msg


port registrationResponse : (String -> msg) -> Sub msg


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
