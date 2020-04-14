port module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode
import ServiceWorker as SW
import Permissions as P


port postMessage : String -> Cmd msg


port updatePosts : (List Post -> msg) -> Sub msg


port refreshPosts : () -> Cmd msg


type alias Model =
    { text : String
    , posts : List Post
    , swavailability : SW.Availability
    , swRegistration : SW.Registration
    , swSubsciption : SW.Subscription
    , swVapidKey : Maybe String
    , permissionStatus : Maybe P.PermissionStatus
    }


type alias Post =
    { text : String
    , sync : String
    }


type Msg
    = TextChanged String
    | SendAndClear
    | PostsChanged (List Post)
    | SWAvailability SW.Availability
    | SWRegistration SW.Registration
    | SWClientUpdate (Result SW.Error SW.ClientState)
    | Subscribe


main : Program () Model Msg
main =
    Browser.document
        { view = view
        , update = update
        , init = init
        , subscriptions = subscriptions
        }


view : Model -> Browser.Document Msg
view model =
    { title = "Elm PWA example"
    , body =
        [ Html.div []
            [ viewPwaInfo model
            , Html.h1 []
                [ text "Hello Elm PWA Example!"
                ]
            , Html.ul []
                (List.map viewPost model.posts)
            , Html.form [ HE.onSubmit SendAndClear ]
                [ Html.input
                    [ HA.value model.text
                    , HE.onInput (\input -> TextChanged input)
                    ]
                    []
                , Html.input [ HA.type_ "submit", HA.value "Senden" ] []
                ]
            ]
        ]
    }


viewPwaInfo : Model -> Html Msg
viewPwaInfo model =
    Html.table []
        [ Html.caption [] [ text "PWA Info" ]
        , Html.tr []
            [ Html.td [] [ text "Service Worker API" ]
            , Html.td []
                [ text <|
                    case model.swavailability of
                        SW.Unknown ->
                            "Unknown"

                        SW.Available ->
                            "Available"

                        SW.NotAvailable ->
                            "Not Available"
                ]
            ]
        , Html.tr []
            [ Html.td [] [ text "Service Worker Registration" ]
            , Html.td []
                [ text <|
                    case model.swRegistration of
                        SW.RegistrationUnknown ->
                            "Unknown"

                        SW.RegistrationSuccess ->
                            "Registered"

                        SW.RegistrationError ->
                            "Registration error"
                ]
            ]
        , Html.tr []
            [ Html.td [] [ text "Service Worker Subscription" ]
            , Html.td []
                [ case model.swSubsciption of
                    SW.NoSubscription ->
                        text "No subscription"

                    SW.Subscribed data ->
                        text ("Subscription:" ++ data.endpoint)
                ]
            ]
        , Html.tr []
            [ Html.td [] [ text "Service Worker VAPID key" ]
            , Html.td []
                [ case model.swVapidKey of
                    Nothing ->
                        text "No VAPID key"

                    Just key ->
                        Html.div []
                            [ text "Has VAPID key"
                            , Html.button
                                [ HE.onClick Subscribe ]
                                [ text "Subscribe" ]
                            ]
                ]
            ]
        , Html.tr []
            [ Html.td [] [ text "Notification Permission" ]
            , Html.td []
                [ case model.permissionStatus of
                    Nothing ->
                        text "Unknown"

                    Just ps ->
                        case ps of
                            P.Granted -> 
                                Html.div []
                                    [ text "Granted" ]
                            _ -> 
                                Html.div []
                                    [ text (P.permissionStatusString ps) 
                                    , Html.button
                                        [ ]
                                        [ text "Subscribe" ]
                                    ]
                ]
            ]
        ]


subscribe : Cmd msg
subscribe =
    SW.postMessage "subscribe"


viewPost : Post -> Html Msg
viewPost post =
    Html.li []
        [ text post.text
        , text
            (case post.sync of
                "PENDING" ->
                    " ⌛"

                _ ->
                    " ✅ "
            )
        ]


init : () -> ( Model, Cmd Msg )
init _ =
    ( { text = ""
      , posts = []
      , swavailability = SW.Unknown
      , swRegistration = SW.RegistrationUnknown
      , swSubsciption = SW.NoSubscription
      , swVapidKey = Nothing
      , permissionStatus = Nothing
      }
    , SW.checkAvailability
    )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ SW.getAvailability SWAvailability
        , SW.getRegistration SWRegistration
        , SW.onClientUpdate SWClientUpdate
        ]


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SendAndClear ->
            ( { model | text = "" }, postMessage model.text )

        TextChanged newText ->
            ( { model | text = newText }, Cmd.none )

        PostsChanged newPosts ->
            ( { model | posts = newPosts }, Cmd.none )

        SWAvailability availability ->
            ( { model | swavailability = availability }
            , if
                availability
                    == SW.Available
                    && (model.swRegistration == SW.RegistrationUnknown)
              then
                SW.register

              else
                Cmd.none
            )

        SWRegistration registration ->
            ( { model | swRegistration = registration }
            , if registration == SW.RegistrationSuccess then
                Cmd.batch [ SW.postMessage "hello", SW.getPushSubscription ]

              else
                Cmd.none
            )

        Subscribe ->
            ( model, subscribe )

        SWClientUpdate result ->
            case result of
                Err _ ->
                    ( model, Cmd.none )

                Ok cu ->
                    ( { model
                        | swSubsciption = cu.subscription
                        , swVapidKey = cu.vapidKey
                        , permissionStatus = cu.permissionStatus
                    }
                    , Cmd.none )
