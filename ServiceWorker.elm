port module ServiceWorker exposing
    ( Availability(..)
    , Registration(..)
    , Subscription
    , checkAvailability
    , getAvailability
    , getPushSubscription
    , getRegistration
    , onMessage
    , postMessage
    , register
    , subscriptionState
    )

import Json.Decode


type Availability
    = Unknown
    | Available
    | NotAvailable


type Registration
    = RegistrationUnknown
    | RegistrationSuccess
    | RegistrationError


type alias Subscription =
    Maybe String


register : Cmd msg
register =
    registrationRequest ()


postMessage : Cmd msg
postMessage =
    postMessageInternal ()


getRegistration : (Registration -> msg) -> Sub msg
getRegistration f =
    registrationResponse (registrationFromString >> f)


getPushSubscription : Cmd msg
getPushSubscription =
    pushSubscriptionRequest ()


registrationFromString : String -> Registration
registrationFromString s =
    if s == "success" then
        RegistrationSuccess

    else
        RegistrationError


port availabilityResponse : (Bool -> msg) -> Sub msg


port availabilityRequest : () -> Cmd msg


port pushSubscriptionRequest : () -> Cmd msg


port postMessageInternal : () -> Cmd msg


port onMessageInternal : (String -> msg) -> Sub msg


port registrationRequest : () -> Cmd msg


port registrationResponse : (String -> msg) -> Sub msg


port sendSubscriptionState : (Json.Decode.Value -> msg) -> Sub msg


subscriptionState : (Result Json.Decode.Error Subscription -> msg) -> Sub msg
subscriptionState msg =
    sendSubscriptionState (subscriptionDecoder >> msg)


{-| TODO try to return Maybe and throw away the error somehow
-}
subscriptionDecoder :
    Json.Decode.Value
    -> Result Json.Decode.Error Subscription
subscriptionDecoder =
    Json.Decode.decodeValue (Json.Decode.nullable Json.Decode.string)


checkAvailability : Cmd msg
checkAvailability =
    availabilityRequest ()


getAvailability : (Availability -> msg) -> Sub msg
getAvailability msg =
    availabilityResponse (availabilityFromBool >> msg)


onMessage : (String -> msg) -> Sub msg
onMessage =
    onMessageInternal


availabilityFromBool : Bool -> Availability
availabilityFromBool b =
    if b then
        Available

    else
        NotAvailable
