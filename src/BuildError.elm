module BuildError exposing (BuildError, encode, errorToString, errorsToString)

import Json.Encode as Encode
import TerminalText as Terminal


type alias BuildError =
    { title : String
    , path : String
    , message : List Terminal.Text
    , fatal : Bool
    }


errorsToString : List BuildError -> String
errorsToString errors =
    errors
        |> List.map errorToString
        |> String.join "\n\n"


errorToString : BuildError -> String
errorToString error =
    banner error.title
        ++ error.message
        |> Terminal.toString


banner : String -> List Terminal.Text
banner title =
    [ Terminal.cyan <|
        ("-- " ++ String.toUpper title ++ " ----------------------------------------------------- elm-pages")
    , Terminal.text "\n\n"
    ]


encode : BuildError -> Encode.Value
encode buildError =
    Encode.object
        [ ( "path", Encode.string buildError.path )
        , ( "name", Encode.string buildError.title )
        , ( "problems", Encode.list (messagesEncoder buildError.title) [ buildError.message ] )
        ]


messagesEncoder : String -> List Terminal.Text -> Encode.Value
messagesEncoder title messages =
    Encode.object
        [ ( "title", Encode.string title )
        , ( "message", Encode.list Terminal.encoder messages )
        ]
