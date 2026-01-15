module Components.ModelGrid exposing (modelGrid, modelGridCompact, modelGridConfig)

import Components.ModelCard exposing (modelCard, modelCardCompact)
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css)
import Styles
import Types exposing (PdfModel, allPdfModels)


type alias ModelGridConfig msg =
    { selectedModel : PdfModel
    , hoveredModel : Maybe PdfModel
    , onSelect : PdfModel -> msg
    , onHover : Maybe PdfModel -> msg
    , models : List PdfModel
    }


modelGridConfig :
    { selectedModel : PdfModel
    , hoveredModel : Maybe PdfModel
    , onSelect : PdfModel -> msg
    , onHover : Maybe PdfModel -> msg
    }
    -> ModelGridConfig msg
modelGridConfig config =
    { selectedModel = config.selectedModel
    , hoveredModel = config.hoveredModel
    , onSelect = config.onSelect
    , onHover = config.onHover
    , models = allPdfModels
    }


{-| Full model grid with standard cards
-}
modelGrid : ModelGridConfig msg -> Html msg
modelGrid config =
    div
        [ css [ Styles.modelCardGrid ] ]
        (List.map (renderCard config) config.models)


{-| Compact 2-column grid for smaller spaces
-}
modelGridCompact :
    { selectedModel : PdfModel
    , onSelect : PdfModel -> msg
    , models : List PdfModel
    }
    -> Html msg
modelGridCompact config =
    div
        [ css [ Styles.modelCardGridCompact ] ]
        (List.map
            (\model ->
                modelCardCompact
                    { model = model
                    , isSelected = model == config.selectedModel
                    , onSelect = config.onSelect
                    }
            )
            config.models
        )


renderCard : ModelGridConfig msg -> PdfModel -> Html msg
renderCard config model =
    modelCard
        { model = model
        , isSelected = model == config.selectedModel
        , isHovered = config.hoveredModel == Just model
        , onSelect = config.onSelect
        , onHover = config.onHover
        }
