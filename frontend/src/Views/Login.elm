module Views.Login exposing (view)

import Components.Button as Button
import Components.Input as Input
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href, type_)
import Html.Styled.Events exposing (onSubmit)
import Styles
import Types exposing (..)


view : Model -> Html Msg
view model =
    div
        [ css
            [ displayFlex
            , alignItems center
            , justifyContent center
            , minHeight (vh 100)
            , padding Styles.spacing.xl
            ]
        ]
        [ div
            [ css
                [ maxWidth (px 420)
                , width (pct 100)
                ]
            ]
            [ -- Logo/Brand
              div
                [ css
                    [ textAlign center
                    , marginBottom Styles.spacing.xxl
                    ]
                ]
                [ div
                    [ css
                        [ Css.fontSize (px 48)
                        , marginBottom Styles.spacing.md
                        ]
                    ]
                    [ text "📄" ]
                , h1
                    [ css
                        [ Styles.textDisplay
                        , marginBottom Styles.spacing.xs
                        ]
                    ]
                    [ text "PDF Models" ]
                , p
                    [ css
                        [ Styles.textSecondary
                        , margin zero
                        ]
                    ]
                    [ text "Document processing platform" ]
                ]

            -- Form card
            , Html.Styled.form
                [ onSubmit SignInClicked
                , css
                    [ backgroundColor Styles.colors.surface
                    , border3 (px 1) solid Styles.colors.border
                    , borderRadius Styles.radius.xl
                    , padding Styles.spacing.xxl
                    ]
                ]
                [ h2
                    [ css
                        [ Styles.textH1
                        , marginBottom Styles.spacing.xl
                        , textAlign center
                        ]
                    ]
                    [ text "Sign In" ]
                , Input.input
                    { label = "Email"
                    , value = model.loginForm.email
                    , onInput = EmailChanged
                    , inputType = "email"
                    , placeholder = "you@example.com"
                    , hasError = False
                    , autocomplete = "username"
                    }
                , Input.input
                    { label = "Password"
                    , value = model.loginForm.password
                    , onInput = PasswordChanged
                    , inputType = "password"
                    , placeholder = "Enter your password"
                    , hasError = False
                    , autocomplete = "current-password"
                    }
                , case model.loginForm.error of
                    Just err ->
                        div
                            [ css
                                [ backgroundColor Styles.colors.errorMuted
                                , border3 (px 1) solid Styles.colors.error
                                , borderRadius Styles.radius.md
                                , padding Styles.spacing.md
                                , marginBottom Styles.spacing.lg
                                , color Styles.colors.error
                                , Css.fontSize Styles.fontSize.small
                                ]
                            ]
                            [ text err ]

                    Nothing ->
                        text ""
                , div [ css [ marginTop Styles.spacing.lg ] ]
                    [ Html.Styled.button
                        [ type_ "submit"
                        , css
                            [ Css.width (pct 100)
                            , padding Styles.spacing.md
                            , backgroundColor Styles.colors.accent
                            , border zero
                            , borderRadius Styles.radius.md
                            , color Styles.colors.textInverse
                            , fontWeight Styles.fontWeights.medium
                            , Css.fontSize Styles.fontSize.body
                            , cursor pointer
                            , Styles.transitions.base
                            , hover
                                [ backgroundColor Styles.colors.accentHover
                                ]
                            , focus
                                [ Styles.focusRing
                                ]
                            ]
                        ]
                        [ text
                            (if model.auth == Authenticating then
                                "Signing in..."

                             else
                                "Sign In"
                            )
                        ]
                    ]
                , div
                    [ css
                        [ marginTop Styles.spacing.xl
                        , textAlign center
                        , Styles.textSmall
                        ]
                    ]
                    [ text "Don't have an account? "
                    , a
                        [ href (routeToPath SignUp)
                        , css
                            [ color Styles.colors.accent
                            , textDecoration none
                            , fontWeight Styles.fontWeights.medium
                            , Styles.transitions.base
                            , hover
                                [ color Styles.colors.accentHover
                                , textDecoration underline
                                ]
                            ]
                        ]
                        [ text "Create account" ]
                    ]
                ]
            ]
        ]
