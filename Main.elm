port module Main exposing (main)

import Html exposing (Html, text)
import Html.Attributes as HA
import Html.Events as HE
import Pwa
import SWClient


port postMessage : String -> Cmd msg


port updatePosts : (List Post -> msg) -> Sub msg


port refreshPosts : () -> Cmd msg


type alias Model =
    { text : String
    , posts : List Post
    , swcmodel : SWClient.Model
    }


type alias Post =
    { text : String
    , sync : String
    }


type Msg
    = TextChanged String
    | SendAndClear
    | PostsChanged (List Post)
    | SWClientMsg SWClient.Msg


main : Program () (Pwa.Model Model) (Pwa.Msg Msg)
main =
    Pwa.app
        { view = view
        , update = update
        , init = init
        , subscriptions = subscriptions
        }


view : Model -> Pwa.App Msg
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
            , Html.map SWClientMsg (SWClient.view model.swcmodel)
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
    let
        ( swcmodel, swccmd ) =
            SWClient.init
    in
    ( { text = ""
      , posts = []
      , swcmodel = swcmodel
      }
    , Cmd.map SWClientMsg swccmd
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ updatePosts PostsChanged
        , Sub.map SWClientMsg (SWClient.subscriptions model.swcmodel)
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

        SWClientMsg swcmsg ->
            let
                ( swcmodel, swccmd ) =
                    SWClient.update swcmsg model.swcmodel
            in
            ( { model | swcmodel = swcmodel }, Cmd.map SWClientMsg swccmd )
