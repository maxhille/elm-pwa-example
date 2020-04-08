port module ServiceWorker exposing
    ( Availability(..)
    , ClientState
    , FetchResult
    , Message(..)
    , Registration(..)
    , Subscription(..)
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
    , subscribe
    , subscriptionState
    , updateClients
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


type alias ClientState =
    { subscription : Subscription
    , vapidKey : Maybe String
    }


type alias FetchResult =
    String


type Message
    = Subscribe
    | Invalid


updateClients : ClientState -> Cmd msg
updateClients state =
    state
        |> encodeClientstate
        |> postMessageInternal


encodeClientstate : ClientState -> JE.Value
encodeClientstate v =
    JE.object
        [ ( "subscription", encodeSubscription v.subscription )
        , ( "vapidKey", encodeMaybeString v.vapidKey )
        ]


encodeMaybeString : Maybe String -> JE.Value
encodeMaybeString ms =
    case ms of
        Nothing ->
            JE.null

        Just s ->
            JE.string s


encodeSubscription : Subscription -> JE.Value
encodeSubscription subscription =
    case subscription of
        NoSubscription ->
            JE.object [ ( "type", JE.string "none" ) ]

        Subscribed data ->
            JE.object
                [ ( "data"
                  , JE.object
                        [ ( "auth", JE.string data.auth )
                        , ( "p256dh", JE.string data.p256dh )
                        , ( "endpoint", JE.string data.endpoint )
                        ]
                  )
                ]


register : Cmd msg
register =
    registrationRequest ()


fetch : Cmd msg
fetch =
    fetchInternal ()


subscribe : String -> Cmd msg
subscribe s =
    subscribeInternal s


postMessage : String -> Cmd msg
postMessage s =
    JE.string s |> postMessageInternal


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


port postMessageInternal : JE.Value -> Cmd msg


port onMessageInternal : (String -> msg) -> Sub msg


port registrationRequest : () -> Cmd msg


port fetchInternal : () -> Cmd msg


port onFetchResultInternal : (String -> msg) -> Sub msg


port registrationResponse : (String -> msg) -> Sub msg


port subscribeInternal : String -> Cmd msg


port sendSubscriptionState : (JD.Value -> msg) -> Sub msg


port sendBroadcast : Bool -> Cmd msg


port receiveBroadcast : (Bool -> msg) -> Sub msg


subscriptionState : (Subscription -> msg) -> Sub msg
subscriptionState msg =
    sendSubscriptionState (subscriptionDecoder >> msg)


subscriptionDecoder : JD.Value -> Subscription
subscriptionDecoder value =
    case JD.decodeValue subscriptionDataDecoder value of
        Err _ ->
            NoSubscription

        Ok data ->
            Subscribed data


subscriptionDataDecoder : JD.Decoder SubscriptionData
subscriptionDataDecoder =
    JD.map3 SubscriptionData
        (JD.at [ "auth" ] JD.string)
        (JD.at [ "p256dh" ] JD.string)
        (JD.at [ "endpoint" ] JD.string)


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
