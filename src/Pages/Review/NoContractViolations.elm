module Pages.Review.NoContractViolations exposing (rule)

{-|

@docs rule

-}

import Dict exposing (Dict)
import Elm.Syntax.Declaration as Declaration exposing (Declaration)
import Elm.Syntax.Exposing as Exposing exposing (Exposing)
import Elm.Syntax.Module as Module exposing (Module)
import Elm.Syntax.Node as Node exposing (Node)
import Elm.Syntax.TypeAnnotation as TypeAnnotation exposing (TypeAnnotation)
import Review.Rule as Rule exposing (Direction, Error, Rule)
import Set exposing (Set)


{-| Reports... REPLACEME

    config =
        [ Pages.Review.NoContractViolations.rule
        ]


## Fail

    a =
        "REPLACEME example to replace"


## Success

    a =
        "REPLACEME example to replace"


## When (not) to enable this rule

This rule is useful when REPLACEME.
This rule is not useful when REPLACEME.


## Try it out

You can try this rule out by running the following command:

```bash
elm-review --template dillonkearns/elm-review-elm-pages/example --rules Pages.Review.NoContractViolations
```

-}
rule : Rule
rule =
    Rule.newModuleRuleSchema "Pages.Review.NoContractViolations"
        { moduleName = []
        , isPageModule = False
        }
        |> Rule.withModuleDefinitionVisitor moduleDefinitionVisitor
        |> Rule.withDeclarationVisitor declarationVisitor
        |> Rule.fromModuleRuleSchema


type alias Context =
    { moduleName : List String
    , isPageModule : Bool
    }


moduleDefinitionVisitor : Node Module -> Context -> ( List (Error {}), Context )
moduleDefinitionVisitor node _ =
    let
        isPageModule : Bool
        isPageModule =
            (Node.value node |> Module.moduleName |> List.take 1)
                == [ "Page" ]
                && ((Node.value node |> Module.moduleName |> List.length) > 1)
    in
    case Node.value node |> Module.exposingList of
        Exposing.All _ ->
            ( []
            , { moduleName = Node.value node |> Module.moduleName
              , isPageModule = isPageModule
              }
            )

        Exposing.Explicit exposedValues ->
            if isPageModule then
                case Set.diff (Set.fromList [ "Data", "Msg", "Model", "page" ]) (exposedNames exposedValues) |> Set.toList of
                    [] ->
                        ( []
                        , { moduleName = Node.value node |> Module.moduleName
                          , isPageModule = isPageModule
                          }
                        )

                    nonEmpty ->
                        ( [ Rule.error
                                { message = "Unexposed Declaration in Page Module"
                                , details =
                                    [ """Page Modules need to expose the following values:

- page
- Data
- Model
- Msg

But it is not exposing: """
                                        ++ (nonEmpty |> String.join ", ")
                                    ]
                                }
                                (Node.range (exposingListNode (Node.value node)))
                          ]
                        , { moduleName = Node.value node |> Module.moduleName
                          , isPageModule = isPageModule
                          }
                        )

            else
                ( []
                , { moduleName = Node.value node |> Module.moduleName
                  , isPageModule = isPageModule
                  }
                )


routeParamsMatchesNameOrError : Node TypeAnnotation -> List String -> List (Error {})
routeParamsMatchesNameOrError annotation moduleName =
    case stringFields annotation of
        Err error ->
            [ error ]

        Ok actualStringFields ->
            let
                expectedFields : Dict String Param
                expectedFields =
                    expectedRouteParamsFromModuleName moduleName
            in
            if actualStringFields == (expectedFields |> Dict.map (\_ value -> Ok value)) then
                []

            else
                [ Rule.error
                    { message = "RouteParams don't match Page Module name"
                    , details =
                        [ """Expected

"""
                            ++ expectedFieldsToRecordString expectedFields
                            ++ "\n"
                        ]
                    }
                    (Node.range annotation)
                ]


expectedFieldsToRecordString : Dict String Param -> String
expectedFieldsToRecordString expectedFields =
    "type alias RouteParams = { "
        ++ (expectedFields
                |> Dict.toList
                |> List.map (\( name, param ) -> name ++ " : " ++ paramToTypeString param)
                |> String.join ", "
           )
        ++ " }"


paramToTypeString : Param -> String
paramToTypeString param =
    case param of
        Required ->
            "String"

        Optional ->
            "Maybe String"

        RequiredSplat ->
            "( String, List String )"

        OptionalSplat ->
            "List String"


expectedRouteParamsFromModuleName : List String -> Dict String Param
expectedRouteParamsFromModuleName moduleSegments =
    case moduleSegments of
        "Page" :: segments ->
            segments
                |> List.filterMap segmentToParam
                |> Dict.fromList

        _ ->
            Dict.empty


type Param
    = Required
    | Optional
    | RequiredSplat
    | OptionalSplat


segmentToParam : String -> Maybe ( String, Param )
segmentToParam segment =
    if segment == "SPLAT__" then
        ( "splat"
        , OptionalSplat
        )
            |> Just

    else if segment == "SPLAT_" then
        ( "splat"
        , RequiredSplat
        )
            |> Just

    else if segment |> String.endsWith "__" then
        ( segment
            |> String.dropRight 2
            |> decapitalize
        , Optional
        )
            |> Just

    else if segment |> String.endsWith "_" then
        ( segment
            |> String.dropRight 1
            |> decapitalize
        , Required
        )
            |> Just

    else
        Nothing


{-| Decapitalize the first letter of a string.
decapitalize "This is a phrase" == "this is a phrase"
decapitalize "Hello, World" == "hello, World"
-}
decapitalize : String -> String
decapitalize word =
    -- Source: https://github.com/elm-community/string-extra/blob/4.0.1/src/String/Extra.elm
    changeCase Char.toLower word


{-| Change the case of the first letter of a string to either uppercase or
lowercase, depending of the value of `wantedCase`. This is an internal
function for use in `toSentenceCase` and `decapitalize`.
-}
changeCase : (Char -> Char) -> String -> String
changeCase mutator word =
    -- Source: https://github.com/elm-community/string-extra/blob/4.0.1/src/String/Extra.elm
    String.uncons word
        |> Maybe.map (\( head, tail ) -> String.cons (mutator head) tail)
        |> Maybe.withDefault ""


stringFields :
    Node TypeAnnotation
    -> Result (Error {}) (Dict String (Result (Node TypeAnnotation) Param))
stringFields typeAnnotation =
    case Node.value typeAnnotation of
        TypeAnnotation.Record recordDefinition ->
            let
                fields : Dict String (Result (Node TypeAnnotation) Param)
                fields =
                    recordDefinition
                        |> List.map Node.value
                        |> List.map
                            (\( name, annotation ) ->
                                ( Node.value name, paramType annotation )
                            )
                        |> Dict.fromList
            in
            Ok fields

        _ ->
            Err
                (Rule.error
                    { message = "RouteParams must be a record type alias."
                    , details =
                        [ """Expected a record type alias."""
                        ]
                    }
                    (Node.range typeAnnotation)
                )


paramType : Node TypeAnnotation -> Result (Node TypeAnnotation) Param
paramType typeAnnotation =
    case Node.value typeAnnotation of
        TypeAnnotation.Tupled [ first, second ] ->
            case ( Node.value first, Node.value second ) of
                ( TypeAnnotation.Typed firstType [], TypeAnnotation.Typed secondType [ listType ] ) ->
                    if
                        (Node.value firstType == ( [], "String" ))
                            && (Node.value secondType == ( [], "List" ))
                            && (Node.value listType |> isString)
                    then
                        Ok RequiredSplat

                    else
                        Err typeAnnotation

                _ ->
                    Err typeAnnotation

        TypeAnnotation.Typed moduleContext innerType ->
            -- TODO need to use module lookup table to handle Basics or aliases?
            case ( Node.value moduleContext, innerType ) of
                ( ( [], "String" ), [] ) ->
                    Ok Required

                ( ( [], "Maybe" ), [ maybeOf ] ) ->
                    if isString (Node.value maybeOf) then
                        Ok Optional

                    else
                        Err typeAnnotation

                ( ( [], "List" ), [ listOf ] ) ->
                    if isString (Node.value listOf) then
                        Ok OptionalSplat

                    else
                        Err typeAnnotation

                _ ->
                    Ok Optional

        _ ->
            Err typeAnnotation


isString : TypeAnnotation -> Bool
isString typeAnnotation =
    case typeAnnotation of
        TypeAnnotation.Typed moduleContext [] ->
            -- TODO need to use module lookup table to handle Basics or aliases?
            Node.value moduleContext == ( [], "String" )

        _ ->
            False


declarationVisitor : Node Declaration -> Direction -> Context -> ( List (Error {}), Context )
declarationVisitor node direction context =
    case ( direction, Node.value node ) of
        ( Rule.OnEnter, Declaration.AliasDeclaration { name, typeAnnotation } ) ->
            -- TODO check that generics is empty
            if context.isPageModule && Node.value name == "RouteParams" then
                ( routeParamsMatchesNameOrError typeAnnotation context.moduleName
                , context
                )

            else
                ( [], context )

        _ ->
            ( [], context )


exposedNames : List (Node Exposing.TopLevelExpose) -> Set String
exposedNames exposedValues =
    exposedValues
        |> List.filterMap (Node.value >> getExposedName)
        |> Set.fromList


getExposedName : Exposing.TopLevelExpose -> Maybe String
getExposedName exposedValue =
    case exposedValue of
        Exposing.FunctionExpose name ->
            Just name

        Exposing.InfixExpose _ ->
            Nothing

        Exposing.TypeOrAliasExpose name ->
            Just name

        Exposing.TypeExpose exposedType ->
            Just exposedType.name


exposingListNode : Module -> Node Exposing
exposingListNode m =
    case m of
        Module.NormalModule x ->
            x.exposingList

        Module.PortModule x ->
            x.exposingList

        Module.EffectModule x ->
            x.exposingList