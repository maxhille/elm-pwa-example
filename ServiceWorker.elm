port module ServiceWorker exposing
    ( Availability(..)
    , FetchResult
    , Message(..)
    , Registration(..)
    , Subscription
    , checkAvailability
    , fetch
    , getAvailability
    , getPushSubscription
    , getRegistration
    , onFetchResult
    , onMessage
    , postMessage
    , register
    , sendBroadcast
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


type alias FetchResult =
    String


type Message
    = Subscribe
    | Invalid


register : Cmd msg
register =
    registrationRequest ()


fetch : Cmd msg
fetch =
    fetchInternal ()


postMessage : String -> Cmd msg
postMessage s =
    postMessageInternal s


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


port postMessageInternal : String -> Cmd msg


port onMessageInternal : (String -> msg) -> Sub msg


port registrationRequest : () -> Cmd msg


port fetchInternal : () -> Cmd msg


port onFetchResultInternal : (String -> msg) -> Sub msg


port registrationResponse : (String -> msg) -> Sub msg


port sendSubscriptionState : (Json.Decode.Value -> msg) -> Sub msg


port sendBroadcast : Bool -> Cmd msg


port receiveBroadcast : (Bool -> msg) -> Sub msg


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


onMessage : (Message -> msg) -> Sub msg
onMessage msg =
    onMessageInternal (decodeMessage >> msg)


onFetchResult : (FetchResult -> msg) -> Sub msg
onFetchResult msg =
    onFetchResultInternal (decodeFetchResult >> msg)


decodeFetchResult : String -> FetchResult
decodeFetchResult s =
    s


decodeMessage : String -> Message
decodeMessage s =
    case s of
        "subscribe" ->
            Subscribe

        _ ->
            Invalid


availabilityFromBool : Bool -> Availability
availabilityFromBool b =
    if b then
        Available

    else
        NotAvailable
