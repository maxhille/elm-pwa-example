module Pwa exposing (App, Model, Msg, app)

import Browser
import Html exposing (Html)


app :
    { init : flags -> ( model, Cmd msg )
    , view : model -> App msg
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    }
    -> Program flags (Model model) (Msg msg)
app impl =
    Browser.document
        { init = init impl.init
        , view = view impl.view
        , update = update impl.update
        , subscriptions = subscriptions impl.subscriptions
        }


type Msg implMsg
    = ImplMsg implMsg


type alias Model model =
    { impl : model
    }


type alias App msg =
    { title : String
    , body : List (Html msg)
    }


view : (model -> App msg) -> Model model -> Browser.Document (Msg msg)
view implView model =
    let
        implDoc =
            implView model.impl
    in
    { title = implDoc.title
    , body = List.map (Html.map ImplMsg) implDoc.body
    }


update :
    (msg -> model -> ( model, Cmd msg ))
    -> Msg msg
    -> Model model
    -> ( Model model, Cmd (Msg msg) )
update implUpdate msg model =
    case msg of
        ImplMsg implMsg ->
            let
                ( implModel, implCmd ) =
                    implUpdate implMsg model.impl
            in
            ( { model | impl = implModel }, Cmd.map ImplMsg implCmd )


init :
    (flags -> ( model, Cmd msg ))
    -> flags
    -> ( Model model, Cmd (Msg msg) )
init implInit flags =
    let
        ( model, cmd ) =
            implInit flags
    in
    ( { impl = model }, Cmd.map ImplMsg cmd )


subscriptions : (model -> Sub msg) -> Model model -> Sub (Msg msg)
subscriptions implsubs model =
    Sub.batch
        [ Sub.map ImplMsg (implsubs model.impl)
        , Sub.none
        ]
