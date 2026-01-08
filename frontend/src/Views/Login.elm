module Views.Login exposing (view)

import Components.Button as Button
import Components.Input as Input
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href)
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
            ]
        ]
        [ div
            [ css
                [ maxWidth (px 400)
                , width (pct 100)
                , padding Styles.spacing.xl
                ]
            ]
            [ h1
                [ css
                    [ Css.fontSize Styles.fontSize.h1
                    , fontWeight Styles.fontWeight.semibold
                    , marginBottom Styles.spacing.xl
                    , textAlign center
                    , color Styles.colors.textPrimary
                    ]
                ]
                [ text "PDF Models" ]
            , Html.Styled.form
                [ onSubmit SignInClicked
                , css
                    [ border3 (px 1) solid Styles.colors.border
                    , padding Styles.spacing.lg
                    , backgroundColor Styles.colors.surface
                    ]
                ]
                [ Input.input
                    { label = "Email"
                    , value = model.loginForm.email
                    , onInput = EmailChanged
                    , inputType = "email"
                    , placeholder = "your@email.com"
                    , hasError = False
                    , autocomplete = "username"
                    }
                , Input.input
                    { label = "Password"
                    , value = model.loginForm.password
                    , onInput = PasswordChanged
                    , inputType = "password"
                    , placeholder = "••••••••"
                    , hasError = False
                    , autocomplete = "current-password"
                    }
                , case model.loginForm.error of
                    Just err ->
                        div
                            [ css
                                [ color Styles.colors.accentError
                                , Css.fontSize Styles.fontSize.small
                                , marginBottom Styles.spacing.sm
                                ]
                            ]
                            [ text err ]

                    Nothing ->
                        text ""
                , div [ css [ marginTop Styles.spacing.md ] ]
                    [ Button.button Button.Primary
                        (if model.auth == Authenticating then
                            "Signing in..."

                         else
                            "Sign In"
                        )
                        SignInClicked
                    ]
                , div
                    [ css
                        [ marginTop Styles.spacing.md
                        , textAlign center
                        , Css.fontSize Styles.fontSize.small
                        , color Styles.colors.textSecondary
                        ]
                    ]
                    [ text "Don't have an account? "
                    , a
                        [ href (routeToPath SignUp)
                        , css
                            [ color Styles.colors.accentPrimary
                            , textDecoration none
                            , hover [ textDecoration underline ]
                            ]
                        ]
                        [ text "Sign Up" ]
                    ]
                ]
            ]
        ]
