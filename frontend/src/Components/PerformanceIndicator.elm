module Components.PerformanceIndicator exposing (benchmarkDisplay, performanceIndicator, performanceIndicatorCompact)

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, title)
import Styles
import Types exposing (BenchmarkScores, PerformanceTier(..), performanceTierToString)


{-| Full performance indicator with icon and label
-}
performanceIndicator : PerformanceTier -> Html msg
performanceIndicator tier =
    let
        ( icon, tierColor ) =
            tierConfig tier
    in
    span
        [ css
            [ displayFlex
            , alignItems center
            , Styles.gap Styles.spacing.xs
            , Css.fontSize Styles.fontSize.caption
            , color tierColor
            ]
        ]
        [ span [ css [ Css.fontSize (px 14) ] ] [ text icon ]
        , text (performanceTierToString tier)
        ]


{-| Compact indicator with just the icon
-}
performanceIndicatorCompact : PerformanceTier -> Html msg
performanceIndicatorCompact tier =
    let
        ( icon, tierColor ) =
            tierConfig tier
    in
    span
        [ css
            [ displayFlex
            , alignItems center
            , justifyContent center
            , Css.width (px 24)
            , Css.height (px 24)
            , backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.md
            , Css.fontSize (px 14)
            , color tierColor
            ]
        , title (performanceTierToString tier)
        ]
        [ text icon ]


{-| Display benchmark scores with accuracy and speed
-}
benchmarkDisplay : Maybe BenchmarkScores -> Html msg
benchmarkDisplay maybeBenchmarks =
    case maybeBenchmarks of
        Nothing ->
            text ""

        Just benchmarks ->
            div
                [ css
                    [ displayFlex
                    , flexDirection column
                    , Styles.gap Styles.spacing.xs
                    ]
                ]
                [ -- Accuracy
                  case benchmarks.accuracy of
                    Just accuracy ->
                        div
                            [ css
                                [ displayFlex
                                , alignItems center
                                , Styles.gap Styles.spacing.sm
                                ]
                            ]
                            [ span
                                [ css
                                    [ Css.fontSize Styles.fontSize.caption
                                    , color Styles.colors.textTertiary
                                    , Css.width (px 60)
                                    ]
                                ]
                                [ text "Accuracy" ]
                            , div
                                [ css
                                    [ flex (int 1)
                                    , Css.height (px 6)
                                    , backgroundColor Styles.colors.surface
                                    , borderRadius Styles.radius.full
                                    , overflow hidden
                                    ]
                                ]
                                [ div
                                    [ css
                                        [ Css.width (pct accuracy)
                                        , Css.height (pct 100)
                                        , backgroundColor (accuracyColor accuracy)
                                        , borderRadius Styles.radius.full
                                        ]
                                    ]
                                    []
                                ]
                            , span
                                [ css
                                    [ Css.fontSize Styles.fontSize.caption
                                    , fontWeight Styles.fontWeights.medium
                                    , color Styles.colors.textSecondary
                                    , Css.width (px 40)
                                    , textAlign right
                                    ]
                                ]
                                [ text (String.fromFloat accuracy ++ "%") ]
                            ]

                    Nothing ->
                        text ""

                -- Speed
                , case benchmarks.speedTier of
                    Just speed ->
                        div
                            [ css
                                [ displayFlex
                                , alignItems center
                                , Styles.gap Styles.spacing.sm
                                ]
                            ]
                            [ span
                                [ css
                                    [ Css.fontSize Styles.fontSize.caption
                                    , color Styles.colors.textTertiary
                                    , Css.width (px 60)
                                    ]
                                ]
                                [ text "Speed" ]
                            , span
                                [ css
                                    [ fontFamilies Styles.codeFontStack
                                    , Css.fontSize Styles.fontSize.caption
                                    , color Styles.colors.textSecondary
                                    ]
                                ]
                                [ text speed ]
                            ]

                    Nothing ->
                        text ""

                -- Source attribution
                , case benchmarks.source of
                    Just source ->
                        span
                            [ css
                                [ Css.fontSize (px 10)
                                , color Styles.colors.textTertiary
                                , fontStyle italic
                                ]
                            ]
                            [ text ("Source: " ++ source) ]

                    Nothing ->
                        text ""
                ]


tierConfig : PerformanceTier -> ( String, Color )
tierConfig tier =
    case tier of
        Fast ->
            ( "⚡", Styles.colors.success )

        Balanced ->
            ( "⚖", Styles.colors.accent )

        HighQuality ->
            ( "🎯", Styles.colors.info )


accuracyColor : Float -> Color
accuracyColor accuracy =
    if accuracy >= 95 then
        Styles.colors.success

    else if accuracy >= 90 then
        Styles.colors.accent

    else if accuracy >= 85 then
        Styles.colors.warning

    else
        Styles.colors.error
