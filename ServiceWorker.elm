port module ServiceWorker exposing
    ( Availability(..)
    , Error
    , Registration(..)
    , checkAvailability
    , getAvailability
    , getRegistration
    , onMessage
    , onSync
    , postMessage
    , register
    , sendBroadcast
    , subscribePush
    )

import Json.Decode as JD
import Json.Encode as JE


type Availability
    = Unknown
    | Available
    | NotAvailable


type Registration
    = RegistrationUnknown
    | RegistrationSuccess
    | RegistrationError


type alias Error =
    String


register : Cmd msg
register =
    registrationRequest ()


subscribePush : String -> Cmd msg
subscribePush s =
    subscribeInternal s


postMessage : JE.Value -> Cmd msg
postMessage =
    postMessageInternal


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


port postMessageInternal : JE.Value -> Cmd msg


port onMessageInternal : (JD.Value -> msg) -> Sub msg


port registrationRequest : () -> Cmd msg


port registrationResponse : (String -> msg) -> Sub msg


port subscribeInternal : String -> Cmd msg


port sendBroadcast : Bool -> Cmd msg


port onSync : (String -> msg) -> Sub msg


checkAvailability : Cmd msg
checkAvailability =
    availabilityRequest ()


getAvailability : (Availability -> msg) -> Sub msg
getAvailability msg =
    availabilityResponse (availabilityFromBool >> msg)


onMessage : (JD.Value -> msg) -> Sub msg
onMessage =
    onMessageInternal


availabilityFromBool : Bool -> Availability
availabilityFromBool b =
    if b then
        Available

    else
        NotAvailable
