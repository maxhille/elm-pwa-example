port module ServiceWorker exposing
    ( Availability(..)
    , ClientMessage(..)
    , ClientState
    , Error
    , FetchResult
    , Registration(..)
    , Subscription(..)
    , checkAvailability
    , fetch
    , getAvailability
    , getPushSubscription
    , getRegistration
    , onClientMessage
    , onClientUpdate
    , onFetchResult
    , onSubscriptionState
    , postMessage
    , register
    , sendBroadcast
    , subscribe
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


type ClientMessage
    = Subscribe


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


type alias Error =
    String


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
                [ ( "type", JE.string "subscribed" )
                , ( "data"
                  , JE.object
                        [ ( "auth", JE.string data.auth )
                        , ( "p256dh", JE.string data.p256dh )
                        , ( "endpoint", JE.string data.endpoint )
                        ]
                  )
                ]


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


port onMessageInternal : (JD.Value -> msg) -> Sub msg


port onClientMessageInternal : (String -> msg) -> Sub msg


port registrationRequest : () -> Cmd msg


port fetchInternal : () -> Cmd msg


port onFetchResultInternal : (String -> msg) -> Sub msg


port registrationResponse : (String -> msg) -> Sub msg


port subscribeInternal : String -> Cmd msg


port onSubscriptionStateInternal : (JD.Value -> msg) -> Sub msg


port sendBroadcast : Bool -> Cmd msg


port receiveBroadcast : (Bool -> msg) -> Sub msg


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


onClientUpdate : (Result Error ClientState -> msg) -> Sub msg
onClientUpdate msg =
    onMessageInternal
        (JD.decodeValue decodeClientState >> mapError >> msg)


onClientMessage : (Result Error ClientMessage -> msg) -> Sub msg
onClientMessage msg =
    onClientMessageInternal
        (JD.decodeString decodeClientMessage >> mapError >> msg)


decodeClientMessage : JD.Decoder ClientMessage
decodeClientMessage =
    JD.string
        |> JD.andThen
            (\v ->
                case v of
                    "subscribe" ->
                        JD.succeed Subscribe

                    _ ->
                        JD.fail <| "unknown message: " ++ v
            )


onFetchResult : (FetchResult -> msg) -> Sub msg
onFetchResult msg =
    onFetchResultInternal (decodeFetchResult >> msg)


decodeFetchResult : String -> FetchResult
decodeFetchResult s =
    s


decodeClientState : JD.Decoder ClientState
decodeClientState =
    JD.map2 ClientState
        (JD.at [ "subscription" ] decodeSubscription)
        (JD.at [ "vapidKey" ] (JD.nullable JD.string))


availabilityFromBool : Bool -> Availability
availabilityFromBool b =
    if b then
        Available

    else
        NotAvailable
