module Views.Login exposing (view)

{-| Login page with split-screen layout matching Pencil design (Btz72)

Left section: Hero with branding and testimonial
Right section: Login form (520px width)

-}

import Components.Button as Button
import Components.Checkbox as Checkbox
import Components.Input as Input
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css, href, type_)
import Html.Styled.Events exposing (onClick, onSubmit)
import Styles
import Types exposing (..)


view : Model -> Html Msg
view model =
    div
        [ css
            [ displayFlex
            , height (vh 100)
            , backgroundColor Styles.colors.background
            , overflow hidden
            ]
        ]
        [ -- Left: Hero section
          heroSection

        -- Right: Login form
        , formSection model
        ]


{-| Left hero section with branding and testimonial
Based on loginLeft (mL9No) from Pencil design
-}
heroSection : Html Msg
heroSection =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , justifyContent spaceBetween
            , flex (int 1)
            , height (pct 100)
            , padding (px 80)
            , backgroundColor Styles.colors.backgroundSidebar
            ]
        ]
        [ -- Top: Logo + Hero
          div
            [ css
                [ displayFlex
                , flexDirection column
                , property "gap" "48px"
                ]
            ]
            [ -- Logo
              logo

            -- Hero content
            , heroContent
            ]

        -- Bottom: Testimonial
        , testimonial
        ]


{-| Logo section (loginLogo - 9r0Ry)
-}
logo : Html Msg
logo =
    div
        [ css
            [ displayFlex
            , alignItems center
            , property "gap" "12px"
            ]
        ]
        [ -- Logo mark
          div
            [ css
                [ width (px 36)
                , height (px 36)
                , border3 (px 1) solid Styles.colors.primary
                , borderRadius zero
                , flexShrink (int 0)
                ]
            ]
            []

        -- Logo text
        , span
            [ css
                [ fontFamilies Styles.displayFontStack
                , fontSize (px 22)
                , fontWeight (int 400)
                , color Styles.colors.foreground
                , letterSpacing (px 1)
                , lineHeight (num 1.2)
                ]
            ]
            [ text "PDF Models" ]
        ]


{-| Hero content section (loginHero - M2qbV)
-}
heroContent : Html Msg
heroContent =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "16px"
            , width (pct 100)
            ]
        ]
        [ -- Hero title
          h1
            [ css
                [ fontFamilies Styles.displayFontStack
                , fontSize (px 42)
                , fontWeight (int 400)
                , color Styles.colors.foreground
                , lineHeight (num 1.2)
                , margin zero
                , whiteSpace preWrap
                ]
            ]
            [ text "Process documents with\nAI-powered precision" ]

        -- Hero description
        , p
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 16)
                , fontWeight (int 400)
                , color Styles.colors.foregroundMuted
                , lineHeight (num 1.6)
                , margin zero
                , maxWidth (px 400)
                ]
            ]
            [ text "Compare and evaluate multiple document processing models. Upload PDFs, select models, and download processed results." ]
        ]


{-| Testimonial section (loginLeftBottom - buphT)
-}
testimonial : Html Msg
testimonial =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "24px"
            , width (pct 100)
            ]
        ]
        [ -- Testimonial quote
          p
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 14)
                , fontStyle italic
                , fontWeight (int 400)
                , color Styles.colors.foregroundMuted
                , lineHeight (num 1.6)
                , margin zero
                , maxWidth (px 400)
                ]
            ]
            [ text "\"PDF Models has transformed how we evaluate document processing solutions. The comparison features saved us weeks of manual testing.\"" ]

        -- Author info
        , div
            [ css
                [ displayFlex
                , alignItems center
                , property "gap" "12px"
                ]
            ]
            [ -- Avatar
              div
                [ css
                    [ displayFlex
                    , alignItems center
                    , justifyContent center
                    , width (px 40)
                    , height (px 40)
                    , border3 (px 1) solid Styles.colors.borderEmphasis
                    , borderRadius zero
                    , flexShrink (int 0)
                    ]
                ]
                [ span
                    [ css
                        [ fontFamilies Styles.fontStack
                        , fontSize (px 14)
                        , fontWeight (int 500)
                        , color Styles.colors.foreground
                        ]
                    ]
                    [ text "SK" ]
                ]

            -- Author details
            , div
                [ css
                    [ displayFlex
                    , flexDirection column
                    , property "gap" "2px"
                    ]
                ]
                [ div
                    [ css
                        [ fontFamilies Styles.fontStack
                        , fontSize (px 13)
                        , fontWeight (int 500)
                        , color Styles.colors.foreground
                        ]
                    ]
                    [ text "Sarah Kim" ]
                , div
                    [ css
                        [ fontFamilies Styles.fontStack
                        , fontSize (px 11)
                        , fontWeight (int 400)
                        , color Styles.colors.foregroundSubtle
                        ]
                    ]
                    [ text "Data Engineer at TechCorp" ]
                ]
            ]
        ]


{-| Right form section (loginRight - 3H9P8)
-}
formSection : Model -> Html Msg
formSection model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , alignItems center
            , justifyContent center
            , width (px 520)
            , height (pct 100)
            , padding2 (px 80) (px 60)
            ]
        ]
        [ loginForm model
        ]


{-| Login form (loginForm - auphN)
-}
loginForm : Model -> Html Msg
loginForm model =
    Html.Styled.form
        [ onSubmit SignInClicked
        , css
            [ displayFlex
            , flexDirection column
            , property "gap" "32px"
            , width (pct 100)
            ]
        ]
        [ -- Form header
          formHeader

        -- Form fields
        , formFields model

        -- Error message
        , case model.loginForm.error of
            Just err ->
                div
                    [ css
                        [ backgroundColor Styles.colors.errorMuted
                        , border3 (px 1) solid Styles.colors.error
                        , borderRadius zero
                        , padding (px 12)
                        , color Styles.colors.error
                        , fontSize (px 13)
                        ]
                    ]
                    [ text err ]

            Nothing ->
                text ""

        -- Actions
        , formActions model

        -- Footer
        , formFooter
        ]


{-| Form header (loginFormHeader - gmCcx)
-}
formHeader : Html Msg
formHeader =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "8px"
            , width (pct 100)
            ]
        ]
        [ h1
            [ css
                [ fontFamilies Styles.displayFontStack
                , fontSize (px 32)
                , fontWeight (int 400)
                , color Styles.colors.foreground
                , margin zero
                ]
            ]
            [ text "Welcome back" ]
        , p
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 14)
                , fontWeight (int 400)
                , color Styles.colors.foregroundMuted
                , margin zero
                ]
            ]
            [ text "Sign in to your account to continue" ]
        ]


{-| Form fields section (loginFormFields - mh7AX)
-}
formFields : Model -> Html Msg
formFields model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "20px"
            , width (pct 100)
            ]
        ]
        [ -- Email input
          Input.input
            { label = "Email address"
            , value = model.loginForm.email
            , onInput = EmailChanged
            , inputType = "email"
            , placeholder = "name@company.com"
            , hasError = False
            , autocomplete = "username"
            }

        -- Password input
        , Input.password
            { label = "Password"
            , value = model.loginForm.password
            , onInput = PasswordChanged
            , placeholder = "Enter your password"
            , hasError = False
            , autocomplete = "current-password"
            , showPassword = model.loginForm.showPassword
            , togglePassword = TogglePasswordVisibility
            }

        -- Remember me + Forgot password row
        , div
            [ css
                [ displayFlex
                , alignItems center
                , justifyContent spaceBetween
                , width (pct 100)
                ]
            ]
            [ Checkbox.checkbox "Remember me" model.loginForm.rememberMe RememberMeChanged
            , a
                [ href "#"
                , css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 13)
                    , fontWeight (int 500)
                    , color Styles.colors.primary
                    , textDecoration none
                    , Styles.transitions.base
                    , hover
                        [ textDecoration underline
                        ]
                    ]
                ]
                [ text "Forgot password?" ]
            ]
        ]


{-| Form actions (loginActions - ymmuI)
-}
formActions : Model -> Html Msg
formActions model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "16px"
            , width (pct 100)
            ]
        ]
        [ -- Sign in button
          if model.auth == Authenticating then
            styled Html.Styled.button
                [ width (pct 100)
                , displayFlex
                , alignItems center
                , justifyContent center
                , padding2 (px 12) (px 24)
                , backgroundColor Styles.colors.border
                , color Styles.colors.foregroundSubtle
                , cursor notAllowed
                , opacity (num 0.5)
                , border zero
                , fontFamilies Styles.fontStack
                , fontSize (px 13)
                , fontWeight (int 500)
                ]
                [ Attr.disabled True
                , Attr.type_ "button"
                ]
                [ text "Signing in..." ]

          else
            styled Html.Styled.button
                [ width (pct 100)
                , displayFlex
                , alignItems center
                , justifyContent center
                , padding2 (px 12) (px 24)
                , backgroundColor Styles.colors.primary
                , color Styles.colors.primaryForeground
                , border zero
                , fontFamilies Styles.fontStack
                , fontSize (px 13)
                , fontWeight (int 500)
                , cursor pointer
                , Styles.transitions.base
                , hover
                    [ backgroundColor Styles.colors.accentHover
                    ]
                ]
                [ onClick SignInClicked
                , Attr.type_ "submit"
                ]
                [ text "Sign in" ]

        -- Divider with "or"
        , div
            [ css
                [ displayFlex
                , alignItems center
                , property "gap" "16px"
                , width (pct 100)
                ]
            ]
            [ div
                [ css
                    [ flex (int 1)
                    , height (px 1)
                    , backgroundColor Styles.colors.border
                    ]
                ]
                []
            , span
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 12)
                    , fontWeight (int 400)
                    , color Styles.colors.foregroundSubtle
                    ]
                ]
                [ text "or" ]
            , div
                [ css
                    [ flex (int 1)
                    , height (px 1)
                    , backgroundColor Styles.colors.border
                    ]
                ]
                []
            ]

        -- Continue with Google button
        , styled Html.Styled.button
            [ width (pct 100)
            , displayFlex
            , alignItems center
            , justifyContent center
            , padding2 (px 12) (px 20)
            , backgroundColor transparent
            , color Styles.colors.foregroundSubtle
            , border3 (px 1) solid Styles.colors.borderButton
            , cursor notAllowed
            , opacity (num 0.5)
            , fontFamilies Styles.fontStack
            , fontSize (px 13)
            , fontWeight (int 500)
            ]
            [ Attr.disabled True
            , Attr.type_ "button"
            ]
            [ text "Continue with Google" ]
        ]


{-| Form footer (loginFooter - hurQ4)
-}
formFooter : Html Msg
formFooter =
    div
        [ css
            [ displayFlex
            , justifyContent center
            , property "gap" "6px"
            , width (pct 100)
            ]
        ]
        [ span
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 13)
                , fontWeight (int 400)
                , color Styles.colors.foregroundMuted
                ]
            ]
            [ text "Don't have an account?" ]
        , a
            [ href (routeToPath SignUp)
            , css
                [ fontFamilies Styles.fontStack
                , fontSize (px 13)
                , fontWeight (int 500)
                , color Styles.colors.primary
                , textDecoration none
                , Styles.transitions.base
                , hover
                    [ textDecoration underline
                    ]
                ]
            ]
            [ text "Sign up" ]
        ]
