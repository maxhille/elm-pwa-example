port module Main exposing (..)

import Html exposing (Html, text)
import Html.Attributes as HA
import Html.Events as HE


port post : String -> Cmd msg


port updatePosts : (List Post -> msg) -> Sub msg


type alias Model =
    { text : String, posts : List Post }


type alias Post =
    { text : String }


type Msg
    = TextChanged String
    | SendAndClear
    | PostsChanged (List Post)


main : Program Never Model Msg
main =
    Html.program { view = view, update = update, init = init, subscriptions = subscriptions }


view : Model -> Html Msg
view model =
    Html.div []
        [ Html.h1 []
            [ text "Hello Elm PWA Example!"
            ]
        , Html.ul []
            (List.map viewPost model.posts)
        , Html.form [ HE.onSubmit SendAndClear ]
            [ Html.input [ HA.value model.text, HE.onInput TextChanged ] []
            , Html.input [ HA.type_ "submit", HA.value "Senden" ] []
            ]
        ]

viewPost: Post -> Html Msg
viewPost post = Html.li [] [text post.text]

init : ( Model, Cmd Msg )
init =
    ( initialModel, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    updatePosts PostsChanged


initialModel : Model
initialModel =
    { text = "", posts = [] }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SendAndClear ->
            ( { model | text = "" }, post model.text )

        TextChanged newText ->
            ( { model | text = newText }, Cmd.none )

        PostsChanged newPosts ->
            ( { model | posts = newPosts }, Cmd.none )
