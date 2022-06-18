module Route.New exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
import Data.Smoothies as Smoothies
import DataSource exposing (DataSource)
import Dict
import Dict.Extra
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import MySession
import Pages.Field as Field
import Pages.FieldRenderer as FieldRenderer
import Pages.Form
import Pages.FormParser as FormParser
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    {}


type alias ActionData =
    {}


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.succeed (DataSource.succeed (Response.render Data))


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    Request.map2 Tuple.pair
        (Request.formParserResultNew [ form ])
        Request.requestTime
        |> MySession.expectSessionDataOrRedirect (Session.get "userId" >> Maybe.map Uuid)
            (\userId ( parsed, requestTime ) session ->
                case parsed of
                    Ok okParsed ->
                        Smoothies.create okParsed
                            |> Request.Hasura.mutationDataSource requestTime
                            |> DataSource.map
                                (\_ ->
                                    ( session
                                    , Route.redirectTo Route.Index
                                    )
                                )

                    Err errors ->
                        DataSource.succeed
                            -- TODO need to render errors here
                            ( session, Response.render {} )
            )


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


form : FormParser.HtmlForm String { name : String, description : String, price : Int, imageUrl : String } Data Msg
form =
    FormParser.andThenNew
        (\name description price imageUrl ->
            FormParser.ok
                { name = name.value
                , description = description.value
                , price = price.value
                , imageUrl = imageUrl.value
                }
        )
        (\info name description price imageUrl ->
            let
                errors field =
                    info.errors
                        |> Dict.get field.name
                        |> Maybe.withDefault []

                errorsView field =
                    (if field.status == Pages.Form.Blurred then
                        field
                            |> errors
                            |> List.map (\error -> Html.li [] [ Html.text error ])

                     else
                        []
                    )
                        |> Html.ul [ Attr.style "color" "red" ]

                fieldView label field =
                    Html.div []
                        [ Html.label []
                            [ Html.text (label ++ " ")
                            , field |> FieldRenderer.input []
                            ]
                        , errorsView field
                        ]
            in
            ( [ Attr.style "display" "flex"
              , Attr.style "flex-direction" "column"
              , Attr.style "gap" "20px"
              ]
            , [ fieldView "Name" name
              , fieldView "Description" description
              , fieldView "Price" price
              , fieldView "Image" imageUrl
              , Html.button [] [ Html.text "Create" ]
              ]
            )
        )
        |> FormParser.field "name" (Field.text |> Field.required "Required")
        |> FormParser.field "description"
            (Field.text
                |> Field.required "Required"
                |> Field.withClientValidation
                    (\description ->
                        ( Just description
                        , if (description |> String.length) < 5 then
                            [ "Description must be at last 5 characters"
                            ]

                          else
                            []
                        )
                    )
            )
        |> FormParser.field "price" (Field.int { invalid = \_ -> "Invalid int" } |> Field.required "Required")
        |> FormParser.field "imageUrl" (Field.text |> Field.required "Required")


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model app =
    let
        pendingCreation : Result (FormParser.FieldErrors String) NewItem
        pendingCreation =
            form
                |> FormParser.runNew app app.data
                |> .result
                |> parseIgnoreErrors
    in
    { title = "New Item"
    , body =
        [ Html.h2 [] [ Html.text "New item" ]
        , FormParser.renderHtml app app.data form
        , pendingCreation
            |> Debug.log "pendingCreation"
            |> Result.toMaybe
            |> Maybe.map pendingView
            |> Maybe.withDefault (Html.div [] [])
        ]
    }


type alias NewItem =
    { name : String, description : String, price : Int, imageUrl : String }


toResult : ( Maybe parsed, FormParser.FieldErrors error ) -> Result (FormParser.FieldErrors error) parsed
toResult ( maybeParsed, fieldErrors ) =
    let
        isEmptyDict : Bool
        isEmptyDict =
            if Dict.isEmpty fieldErrors then
                True

            else
                fieldErrors
                    |> Dict.Extra.any (\_ errors -> List.isEmpty errors)
    in
    case ( maybeParsed, isEmptyDict ) of
        ( Just parsed, True ) ->
            Ok parsed

        _ ->
            Err fieldErrors


parseIgnoreErrors : ( Maybe parsed, FormParser.FieldErrors error ) -> Result (FormParser.FieldErrors error) parsed
parseIgnoreErrors ( maybeParsed, fieldErrors ) =
    case maybeParsed of
        Just parsed ->
            Ok parsed

        _ ->
            Err fieldErrors


pendingView : NewItem -> Html (Pages.Msg.Msg Msg)
pendingView item =
    Html.div [ Attr.class "item" ]
        [ Html.h2 [] [ Html.text "Preview" ]
        , Html.div []
            [ Html.h3 [] [ Html.text item.name ]
            , Html.p [] [ Html.text item.description ]
            , Html.p [] [ "$" ++ String.fromInt item.price |> Html.text ]
            ]
        , Html.div []
            [ Html.img
                [ Attr.src (item.imageUrl ++ "?ixlib=rb-1.2.1&raw_url=true&q=80&fm=jpg&crop=entropy&cs=tinysrgb&auto=format&fit=crop&w=600&h=903") ]
                []
            ]
        ]