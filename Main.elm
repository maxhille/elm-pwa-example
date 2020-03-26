port module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Html.Attributes as HA
import Html.Events as HE
import ServiceWorker as SW


port postMessage : String -> Cmd msg


port updatePosts : (List Post -> msg) -> Sub msg


port refreshPosts : () -> Cmd msg


type alias Model =
    { text : String
    , posts : List Post
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
            [ Html.h1 []
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
      }
    , SW.checkAvailability
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    SW.getAvailability SWAvailability


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SendAndClear ->
            ( { model | text = "" }, postMessage model.text )

        TextChanged newText ->
            ( { model | text = newText }, Cmd.none )

        PostsChanged newPosts ->
            ( { model | posts = newPosts }, Cmd.none )

        SWAvailability available ->
            ( model, Cmd.none )
