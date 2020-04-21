port module ServiceWorker exposing
    ( Availability(..)
    , Error
    , Registration(..)
    , Subscription(..)
    , SubscriptionData
    , checkAvailability
    , decodeSubscription
    , getAvailability
    , getRegistration
    , onMessage
    , onSubscriptionState
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


type Subscription
    = NoSubscription
    | Subscribed SubscriptionData


type alias SubscriptionData =
    { auth : String
    , p256dh : String
    , endpoint : String
    }


type alias Error =
    String


decodeSubscription : JD.Decoder Subscription
decodeSubscription =
    JD.field "type" JD.string
        |> JD.andThen
            (\typ ->
                case typ of
                    "none" ->
                        JD.succeed NoSubscription

                    _ ->
                        JD.fail <| "unknown type: " ++ typ
            )


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


port onSubscriptionStateInternal : (JD.Value -> msg) -> Sub msg


port sendBroadcast : Bool -> Cmd msg


onSubscriptionState : (Result Error Subscription -> msg) -> Sub msg
onSubscriptionState msg =
    onSubscriptionStateInternal
        (JD.decodeValue decodeSubscription
            >> mapError
            >> msg
        )


mapError : Result JD.Error a -> Result Error a
mapError =
    Result.mapError JD.errorToString


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
