module TypesTest exposing (suite)

import Expect
import Test exposing (..)
import Types exposing (..)


suite : Test
suite =
    describe "Types module"
        [ pdfModelConversionTests
        , modelFilterTests
        , modelMetadataTests
        , routeTests
        ]



-- PDF MODEL CONVERSION TESTS


pdfModelConversionTests : Test
pdfModelConversionTests =
    describe "PdfModel conversion"
        [ describe "pdfModelToString"
            [ test "converts Marker to 'marker'" <|
                \_ ->
                    pdfModelToString Marker
                        |> Expect.equal "marker"
            , test "converts Dolphin to 'dolphin'" <|
                \_ ->
                    pdfModelToString Dolphin
                        |> Expect.equal "dolphin"
            , test "converts Docling to 'docling'" <|
                \_ ->
                    pdfModelToString Docling
                        |> Expect.equal "docling"
            , test "converts DeepSeekOcr to 'deepseek-ocr'" <|
                \_ ->
                    pdfModelToString DeepSeekOcr
                        |> Expect.equal "deepseek-ocr"
            , test "converts MinerU to 'mineru'" <|
                \_ ->
                    pdfModelToString MinerU
                        |> Expect.equal "mineru"
            , test "converts OlmOcr to 'olmocr'" <|
                \_ ->
                    pdfModelToString OlmOcr
                        |> Expect.equal "olmocr"
            , test "converts Docext to 'docext'" <|
                \_ ->
                    pdfModelToString Docext
                        |> Expect.equal "docext"
            ]
        , describe "stringToPdfModel"
            [ test "parses 'marker' to Marker" <|
                \_ ->
                    stringToPdfModel "marker"
                        |> Expect.equal (Just Marker)
            , test "parses 'dolphin' to Dolphin" <|
                \_ ->
                    stringToPdfModel "dolphin"
                        |> Expect.equal (Just Dolphin)
            , test "parses 'docling' to Docling" <|
                \_ ->
                    stringToPdfModel "docling"
                        |> Expect.equal (Just Docling)
            , test "parses 'deepseek-ocr' to DeepSeekOcr" <|
                \_ ->
                    stringToPdfModel "deepseek-ocr"
                        |> Expect.equal (Just DeepSeekOcr)
            , test "parses 'mineru' to MinerU" <|
                \_ ->
                    stringToPdfModel "mineru"
                        |> Expect.equal (Just MinerU)
            , test "parses 'olmocr' to OlmOcr" <|
                \_ ->
                    stringToPdfModel "olmocr"
                        |> Expect.equal (Just OlmOcr)
            , test "parses 'docext' to Docext" <|
                \_ ->
                    stringToPdfModel "docext"
                        |> Expect.equal (Just Docext)
            , test "returns Nothing for unknown model" <|
                \_ ->
                    stringToPdfModel "unknown"
                        |> Expect.equal Nothing
            , test "returns Nothing for empty string" <|
                \_ ->
                    stringToPdfModel ""
                        |> Expect.equal Nothing
            , test "is case sensitive (MARKER returns Nothing)" <|
                \_ ->
                    stringToPdfModel "MARKER"
                        |> Expect.equal Nothing
            ]
        , describe "roundtrip conversion"
            [ test "all models roundtrip correctly" <|
                \_ ->
                    allPdfModels
                        |> List.map (\m -> stringToPdfModel (pdfModelToString m))
                        |> Expect.equal (List.map Just allPdfModels)
            ]
        ]



-- MODEL FILTER TESTS


modelFilterTests : Test
modelFilterTests =
    describe "Model filtering"
        [ describe "filterByCategory"
            [ test "returns all models when no categories specified" <|
                \_ ->
                    filterByCategory [] allPdfModels
                        |> Expect.equal allPdfModels
            , test "filters to OcrConversion models" <|
                \_ ->
                    filterByCategory [ OcrConversion ] allPdfModels
                        |> List.map pdfModelToString
                        |> Expect.equal [ "marker", "deepseek-ocr", "olmocr", "docext", "lightonocr" ]
            , test "filters to LayoutAnalysis models" <|
                \_ ->
                    filterByCategory [ LayoutAnalysis ] allPdfModels
                        |> List.map pdfModelToString
                        |> Expect.equal [ "dolphin", "dots-ocr" ]
            , test "filters to DocumentUnderstanding models" <|
                \_ ->
                    filterByCategory [ DocumentUnderstanding ] allPdfModels
                        |> List.map pdfModelToString
                        |> Expect.equal [ "docling", "mineru" ]
            , test "filters to multiple categories" <|
                \_ ->
                    filterByCategory [ OcrConversion, LayoutAnalysis ] allPdfModels
                        |> List.length
                        |> Expect.equal 7
            ]
        , describe "filterByCapabilities"
            [ test "returns all models when no capabilities specified" <|
                \_ ->
                    filterByCapabilities [] allPdfModels
                        |> Expect.equal allPdfModels
            , test "filters to models with Handwriting capability" <|
                \_ ->
                    filterByCapabilities [ Handwriting ] allPdfModels
                        |> List.map pdfModelToString
                        |> Expect.equal [ "deepseek-ocr", "docext" ]
            , test "filters to models with CustomPrompts capability" <|
                \_ ->
                    filterByCapabilities [ CustomPrompts ] allPdfModels
                        |> List.map pdfModelToString
                        |> Expect.equal [ "dolphin", "deepseek-ocr", "olmocr", "docext", "dots-ocr" ]
            ]
        , describe "filterByComputeType"
            [ test "returns all models when no compute types specified" <|
                \_ ->
                    filterByComputeType [] allPdfModels
                        |> Expect.equal allPdfModels
            , test "filters to CPU models" <|
                \_ ->
                    filterByComputeType [ CpuCompute ] allPdfModels
                        |> List.map pdfModelToString
                        |> Expect.equal [ "marker", "docling", "mineru" ]
            , test "filters to GPU models" <|
                \_ ->
                    filterByComputeType [ GpuCompute ] allPdfModels
                        |> List.map pdfModelToString
                        |> Expect.equal [ "dolphin", "deepseek-ocr", "olmocr", "docext", "dots-ocr", "lightonocr" ]
            ]
        , describe "filterBySearch"
            [ test "returns all models when search query is empty" <|
                \_ ->
                    filterBySearch "" allPdfModels
                        |> Expect.equal allPdfModels
            , test "returns all models when search query is whitespace" <|
                \_ ->
                    filterBySearch "   " allPdfModels
                        |> Expect.equal allPdfModels
            , test "filters by model name" <|
                \_ ->
                    filterBySearch "marker" allPdfModels
                        |> List.map pdfModelToString
                        |> Expect.equal [ "marker" ]
            , test "filters by producer name" <|
                \_ ->
                    filterBySearch "IBM" allPdfModels
                        |> List.map pdfModelToString
                        |> Expect.equal [ "docling" ]
            , test "search is case insensitive" <|
                \_ ->
                    filterBySearch "MARKER" allPdfModels
                        |> List.map pdfModelToString
                        |> Expect.equal [ "marker" ]
            , test "filters by description content" <|
                \_ ->
                    filterBySearch "handwriting" allPdfModels
                        |> List.length
                        |> Expect.atLeast 1
            ]
        , describe "filterModels (combined)"
            [ test "applies all filters" <|
                \_ ->
                    let
                        filters =
                            { categories = [ OcrConversion ]
                            , capabilities = [ CustomPrompts ]
                            , computeTypes = [ GpuCompute ]
                            }
                    in
                    filterModels filters "" allPdfModels
                        |> List.map pdfModelToString
                        |> Expect.equal [ "deepseek-ocr", "olmocr", "docext" ]
            , test "combines filters with search" <|
                \_ ->
                    let
                        filters =
                            { categories = []
                            , capabilities = []
                            , computeTypes = [ GpuCompute ]
                            }
                    in
                    filterModels filters "ocr" allPdfModels
                        |> List.length
                        |> Expect.atLeast 1
            ]
        , describe "hasActiveFilters"
            [ test "returns False for empty filters" <|
                \_ ->
                    hasActiveFilters { categories = [], capabilities = [], computeTypes = [] }
                        |> Expect.equal False
            , test "returns True when categories are set" <|
                \_ ->
                    hasActiveFilters { categories = [ OcrConversion ], capabilities = [], computeTypes = [] }
                        |> Expect.equal True
            , test "returns True when capabilities are set" <|
                \_ ->
                    hasActiveFilters { categories = [], capabilities = [ TableExtraction ], computeTypes = [] }
                        |> Expect.equal True
            , test "returns True when compute types are set" <|
                \_ ->
                    hasActiveFilters { categories = [], capabilities = [], computeTypes = [ GpuCompute ] }
                        |> Expect.equal True
            ]
        ]



-- MODEL METADATA TESTS


modelMetadataTests : Test
modelMetadataTests =
    describe "Model metadata"
        [ describe "modelSupportsPrompt"
            [ test "Dolphin supports prompts" <|
                \_ ->
                    modelSupportsPrompt Dolphin
                        |> Expect.equal True
            , test "DeepSeekOcr supports prompts" <|
                \_ ->
                    modelSupportsPrompt DeepSeekOcr
                        |> Expect.equal True
            , test "OlmOcr supports prompts" <|
                \_ ->
                    modelSupportsPrompt OlmOcr
                        |> Expect.equal True
            , test "Docext supports prompts" <|
                \_ ->
                    modelSupportsPrompt Docext
                        |> Expect.equal True
            , test "Marker does not support prompts" <|
                \_ ->
                    modelSupportsPrompt Marker
                        |> Expect.equal False
            , test "Docling does not support prompts" <|
                \_ ->
                    modelSupportsPrompt Docling
                        |> Expect.equal False
            , test "MinerU does not support prompts" <|
                \_ ->
                    modelSupportsPrompt MinerU
                        |> Expect.equal False
            ]
        , describe "defaultPromptForModel"
            [ test "returns prompt for Dolphin" <|
                \_ ->
                    defaultPromptForModel Dolphin
                        |> Expect.notEqual Nothing
            , test "returns Nothing for Marker" <|
                \_ ->
                    defaultPromptForModel Marker
                        |> Expect.equal Nothing
            , test "prompt models have default prompts" <|
                \_ ->
                    allPdfModels
                        |> List.filter modelSupportsPrompt
                        |> List.all (\m -> defaultPromptForModel m /= Nothing)
                        |> Expect.equal True
            , test "non-prompt models have no default prompts" <|
                \_ ->
                    allPdfModels
                        |> List.filter (not << modelSupportsPrompt)
                        |> List.all (\m -> defaultPromptForModel m == Nothing)
                        |> Expect.equal True
            ]
        , describe "modelMetadata consistency"
            [ test "all models have non-empty descriptions" <|
                \_ ->
                    allPdfModels
                        |> List.all (\m -> String.length (modelMetadata m).description > 0)
                        |> Expect.equal True
            , test "all models have producers" <|
                \_ ->
                    allPdfModels
                        |> List.all (\m -> String.length (modelMetadata m).producer > 0)
                        |> Expect.equal True
            , test "all models have at least one capability" <|
                \_ ->
                    allPdfModels
                        |> List.all (\m -> List.length (modelMetadata m).capabilities > 0)
                        |> Expect.equal True
            , test "all models have bestFor recommendations" <|
                \_ ->
                    allPdfModels
                        |> List.all (\m -> List.length (modelMetadata m).bestFor > 0)
                        |> Expect.equal True
            ]
        ]



-- ROUTE TESTS


routeTests : Test
routeTests =
    describe "Route helpers"
        [ describe "routeToPath"
            [ test "Login route" <|
                \_ ->
                    routeToPath Login
                        |> Expect.equal "/login"
            , test "SignUp route" <|
                \_ ->
                    routeToPath SignUp
                        |> Expect.equal "/signup"
            , test "Jobs route" <|
                \_ ->
                    routeToPath Jobs
                        |> Expect.equal "/jobs"
            , test "Models route" <|
                \_ ->
                    routeToPath Models
                        |> Expect.equal "/models"
            , test "Upload route with Marker" <|
                \_ ->
                    routeToPath (Upload Marker)
                        |> Expect.equal "/upload/marker"
            , test "Upload route with DeepSeekOcr" <|
                \_ ->
                    routeToPath (Upload DeepSeekOcr)
                        |> Expect.equal "/upload/deepseek-ocr"
            ]
        ]
