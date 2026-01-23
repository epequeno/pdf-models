module Components.ProgressBar exposing (progressBar)

{-| ProgressBar component matching Pencil design (WXaM2)

  - width=200px (default)
  - height=8px
  - fill=$--border (background)
  - inner fill=$--primary (progress)

-}

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css)
import Styles


{-| Progress bar component

    progressBar 0.75 -- 75% progress

-}
progressBar : Float -> Html msg
progressBar progress =
    progressBarWithWidth 200 progress


{-| Progress bar with custom width

    progressBarWithWidth 300 0.5 -- 50% progress, 300px wide

-}
progressBarWithWidth : Float -> Float -> Html msg
progressBarWithWidth width progress =
    let
        -- Clamp progress between 0 and 1
        clampedProgress =
            max 0 (min 1 progress)

        progressPercent =
            clampedProgress * 100
    in
    div
        [ css (progressBarContainerStyles width)
        ]
        [ div
            [ css (progressBarFillStyles progressPercent)
            ]
            []
        ]


{-| Container styles - background bar
-}
progressBarContainerStyles : Float -> List Style
progressBarContainerStyles width =
    [ Css.width (px width)
    , Css.height (px 8)
    , backgroundColor Styles.colors.border
    , borderRadius zero
    , overflow hidden
    , position relative
    ]


{-| Fill styles - progress indicator
-}
progressBarFillStyles : Float -> List Style
progressBarFillStyles widthPercent =
    [ Css.height (pct 100)
    , Css.width (pct widthPercent)
    , backgroundColor Styles.colors.primary
    , borderRadius zero
    , Styles.transitions.base
    ]
