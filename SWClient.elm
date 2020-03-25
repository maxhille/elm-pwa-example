port module SWClient exposing
    ( Model
    , Msg
    , init
    , subscriptions
    , update
    , view
    )

import Html exposing (Html, div, text)


type Availability
    = Unknown
    | Available
    | NotAvailable


type Msg
    = Availability Availability


type alias Model =
    { availability : Availability }


init : ( Model, Cmd Msg )
init =
    ( { availability = Unknown
      }
    , availabilityRequest ()
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Availability availability ->
            ( { model | availability = availability }, Cmd.none )


view : Model -> Html Msg
view model =
    div []
        [ formatAvailability model.availability |> text
        ]


formatAvailability : Availability -> String
formatAvailability availability =
    case availability of
        Unknown ->
            "Unknown"

        Available ->
            "Available"

        NotAvailable ->
            "NotAvailable"


port availabilityResponse : (Bool -> msg) -> Sub msg


port availabilityRequest : () -> Cmd msg


subscriptions : Model -> Sub Msg
subscriptions _ =
    availabilityResponse
        (\b ->
            Availability
                (if b then
                    Available

                 else
                    NotAvailable
                )
        )
