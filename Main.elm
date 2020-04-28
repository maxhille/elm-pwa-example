port module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as JD
import Permissions as P
import ServiceWorker as SW
import Worker as W


port postMessage : String -> Cmd msg


port updatePosts : (List Post -> msg) -> Sub msg


port refreshPosts : () -> Cmd msg


type alias Model =
    { text : String
    , posts : List Post
    , swavailability : SW.Availability
    , swRegistration : SW.Registration
    , swSubscription : Maybe W.Subscription
    , swVapidKey : Maybe String
    , permissionStatus : Maybe P.PermissionStatus
    , loggedIn : Maybe Bool
    , loginForm : LoginForm
    }


type alias LoginForm =
    String


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
    | SWClientUpdate (Result JD.Error W.ClientState)
    | Subscribe String
    | RequestPermission
    | ChangedName String
    | Login
    | Logout


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
            , Html.h1 [] [ text "Hello Elm PWA Example!" ]
            , case model.loggedIn of
                Nothing ->
                    text "getting log in state..."

                Just b ->
                    if b then
                        viewChat model

                    else
                        viewLogin model.loginForm
            ]
        ]
    }


viewLogin : LoginForm -> Html Msg
viewLogin form =
    Html.div []
        [ Html.form [ HE.onSubmit Login ]
            [ Html.fieldset []
                [ Html.input
                    [ HA.value form
                    , HE.onInput ChangedName
                    , HA.placeholder "username"
                    ]
                    []
                ]
            , Html.button [] [ text "log in" ]
            ]
        ]


viewChat : Model -> Html Msg
viewChat model =
    Html.div []
        [ Html.button [ HE.onClick Logout ] [ text "Logout" ]
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
                [ case model.swSubscription of
                    Nothing ->
                        text "unknown"

                    Just subscription ->
                        case subscription of
                            W.NoSubscription ->
                                text "No subscription"

                            W.Subscribed data ->
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
                                [ HE.onClick (Subscribe key) ]
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

                            P.Prompt ->
                                Html.div []
                                    [ text (P.permissionStatusString ps)
                                    , Html.button
                                        [ HE.onClick RequestPermission ]
                                        [ text "Request" ]
                                    ]

                            P.Denied ->
                                Html.div []
                                    [ text (P.permissionStatusString ps)
                                    ]
                ]
            ]
        ]


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
      , swSubscription = Nothing
      , swVapidKey = Nothing
      , permissionStatus = Nothing
      , loginForm = ""
      , loggedIn = Nothing
      }
    , SW.checkAvailability
    )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ SW.getAvailability SWAvailability
        , SW.getRegistration SWRegistration
        , W.onClientUpdate SWClientUpdate
        ]


login : LoginForm -> Cmd msg
login form =
    W.Login form
        |> W.sendMessage


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SendAndClear ->
            ( { model | text = "" }, postMessage model.text )

        TextChanged newText ->
            ( { model | text = newText }, Cmd.none )

        PostsChanged newPosts ->
            ( { model | posts = newPosts }, Cmd.none )

        ChangedName name ->
            ( { model | loginForm = name }, Cmd.none )

        Login ->
            ( model, login model.loginForm )

        Logout ->
            ( model, W.logout )

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
                Cmd.batch [ W.sendMessage W.Hello ]

              else
                Cmd.none
            )

        Subscribe key ->
            ( model, W.sendMessage (W.Subscribe key) )

        SWClientUpdate result ->
            case result of
                Err err ->
                    let
                        _ =
                            Debug.log "ClientUpdate" err
                    in
                    ( model, Cmd.none )

                Ok cu ->
                    ( { model
                        | swSubscription = cu.subscription
                        , swVapidKey = cu.vapidKey
                        , permissionStatus = cu.permissionStatus
                        , loggedIn =
                            Maybe.map
                                (\auth ->
                                    case auth of
                                        W.LoggedOut ->
                                            False

                                        W.LoggedIn _ ->
                                            True
                                )
                                cu.auth
                      }
                    , Cmd.none
                    )

        RequestPermission ->
            ( model, P.requestPermission )
