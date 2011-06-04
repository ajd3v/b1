module B1.Program.Chart.Graph
  ( GraphInput(..)
  , GraphOutput(..)
  , GraphState
  , GraphBoundSet(..)
  , drawGraph
  , newGraphState
  , cleanGraphState
  ) where

import Data.Maybe
import Graphics.Rendering.OpenGL

import B1.Data.List
import B1.Data.Price
import B1.Data.Range
import B1.Data.Technicals.MovingAverage
import B1.Data.Technicals.Stochastic
import B1.Data.Technicals.StockData
import B1.Graphics.Rendering.OpenGL.Box
import B1.Graphics.Rendering.OpenGL.LineSegment
import B1.Graphics.Rendering.OpenGL.Shapes
import B1.Graphics.Rendering.OpenGL.Utils
import B1.Graphics.Rendering.FTGL.Utils
import B1.Program.Chart.Animation
import B1.Program.Chart.Colors
import B1.Program.Chart.Dirty
import B1.Program.Chart.FragmentShader
import B1.Program.Chart.GraphUtils
import B1.Program.Chart.Resources
import B1.Program.Chart.StochasticColors
import B1.Program.Chart.Vbo

import qualified B1.Program.Chart.Candlesticks as C
import qualified B1.Program.Chart.StochasticLines as S
import qualified B1.Program.Chart.VolumeBars as V

data GraphInput = GraphInput
  { bounds :: Box
  , alpha :: GLfloat
  , stockData :: StockData
  , inputState :: GraphState
  }

data GraphOutput = GraphOutput
  { outputState :: GraphState
  , isDirty :: Dirty
  }

data GraphState = GraphState
  { maybeVbo :: Maybe Vbo
  , alphaAnimation :: Animation (GLfloat, Dirty)
  , dataStatus :: DataStatus
  , boundSet :: GraphBoundSet
  }

data DataStatus = Loading | Received

data GraphBoundSet = GraphBoundSet
  { graphBounds :: Maybe Box
  , volumeBounds :: Maybe Box
  , stochasticsBounds :: Maybe Box
  , weeklyStochasticsBounds :: Maybe Box
  , dividerLines :: [LineSegment]
  }

newGraphState :: GraphBoundSet -> GraphState
newGraphState boundSet =
  GraphState
    { maybeVbo = Nothing
    , alphaAnimation = animateOnce $ linearRange 0 0 1
    , dataStatus = Loading
    , boundSet = boundSet
    }

cleanGraphState :: GraphState -> IO GraphState
cleanGraphState state@GraphState { maybeVbo = maybeVbo } =
  case maybeVbo of
    Just vbo -> do
      deleteVbo vbo
      return state { maybeVbo = Nothing }
    _ -> return state

drawGraph :: Resources -> GraphInput -> IO GraphOutput
drawGraph resources
    input@GraphInput
      { stockData = stockData
      , inputState = state
      } = do
  maybePriceData <- getStockPriceData stockData
  case maybePriceData of
    Just priceDataOrError ->
      either (renderPriceData resources input)
          (renderError resources input)
          priceDataOrError
    _ -> renderLoading resources input

renderPriceData :: Resources -> GraphInput -> StockPriceData
    -> IO GraphOutput
renderPriceData
    resources@Resources { program = program }
    input@GraphInput
      { bounds = bounds
      , alpha = alpha
      , inputState = state@GraphState
        { maybeVbo = maybeVbo
        , alphaAnimation = alphaAnimation
        , dataStatus = dataStatus
        , boundSet = boundSet
        }
      }
    priceData = do

  vbo <- maybe (createGraphVbo boundSet priceData) return maybeVbo

  preservingMatrix $ do
    scale3 (boxWidth bounds / 2) (boxHeight bounds / 2) 1 
    currentProgram $= Just program
    setAlpha program finalAlpha
    renderVbo vbo
    currentProgram $= Nothing

    let frameColor = outlineColor resources bounds finalAlpha
    mapM_ (\(LineSegment (x1, y1) (x2, y2)) -> do
        renderPrimitive Lines $ do
          color frameColor
          vertex $ vertex2 x1 y1
          vertex $ vertex2 x2 y2
        ) (dividerLines boundSet)

  return GraphOutput
    { outputState = state
      { maybeVbo = Just vbo
      , alphaAnimation = nextAlphaAnimation
      , dataStatus = Received
      }
    , isDirty = nextIsDirty
    }
  where
    currentAlphaAnimation = case dataStatus of
        Loading -> animateOnce $ linearRange 0 1 30
        Received -> alphaAnimation
    finalAlpha = (min alpha . fst . current) currentAlphaAnimation
    nextAlphaAnimation = next currentAlphaAnimation
    nextIsDirty = (snd . current) nextAlphaAnimation

createGraphVbo :: GraphBoundSet -> StockPriceData -> IO Vbo
createGraphVbo boundSet priceData = 
  createVbo $ concat
    [ getVboSpecList graphBounds $
        getVboSpecs priceData
    , getVboSpecList volumeBounds $
        V.getVboSpecs priceData
    , getVboSpecList stochasticsBounds $
        S.getVboSpecs priceData dailySpecs 
    , getVboSpecList weeklyStochasticsBounds $
        S.getVboSpecs priceData weeklySpecs
    ]
  where
    getVboSpecList :: (GraphBoundSet -> Maybe Box) -> (Box -> [VboSpec])
        -> [VboSpec]
    getVboSpecList boundFunc vboFunc = case boundFunc boundSet of 
      Just bounds -> vboFunc bounds
      _ -> []

    dailySpecs =
      [ S.StochasticLineSpec 
        { S.timeSpec = S.Daily
        , S.lineColor = red3
        , S.stochasticFunction = k
        }
      , S.StochasticLineSpec
        { S.timeSpec = S.Daily
        , S.lineColor = yellow3
        , S.stochasticFunction = d
        }
      ]

    weeklySpecs =
      [ S.StochasticLineSpec 
        { S.timeSpec = S.Weekly
        , S.lineColor = red3
        , S.stochasticFunction = k
        }
      , S.StochasticLineSpec
        { S.timeSpec = S.Weekly
        , S.lineColor = purple3
        , S.stochasticFunction = d
        }
      ]

-- TODO: Move the code into a different module
getVboSpecs :: StockPriceData -> Box -> [VboSpec]
getVboSpecs priceData bounds =
  C.getVboSpecs priceData bounds
      ++ getMovingAverageVboSpecs priceData bounds

getMovingAverageVboSpecs :: StockPriceData -> Box -> [VboSpec]
getMovingAverageVboSpecs priceData bounds =
  map (uncurry (createMovingAverageVboSpec priceData bounds)) 
      movingAverageFunctions
  where
    movingAverageFunctions =
      [ (movingAverage25, purple3)
      , (movingAverage50, yellow3)
      , (movingAverage200, white3)
      ]

createMovingAverageVboSpec :: StockPriceData -> Box
    -> (StockPriceData -> [MovingAverage]) -> Color3 GLfloat -> VboSpec
createMovingAverageVboSpec priceData bounds movingAverageFunction color =
  VboSpec LineStrip size elements
  where
    size = getMovingAverageSize priceData movingAverageFunction
    elements = getMovingAverageLines priceData bounds
        movingAverageFunction color

getMovingAverageSize :: StockPriceData
    -> (StockPriceData -> [MovingAverage]) -> Int
getMovingAverageSize priceData movingAverageFunction =
  getLineSize $ trim $ movingAverageFunction priceData
  where
    trim = take $ numDailyElements priceData

getLineSize :: [a] -> Int
getLineSize list = size
  where
    numElements = length list
    floatsPerVertex = 2 + 3 -- x, y, and 3 for color
    size = numElements * floatsPerVertex

getMovingAverageLines :: StockPriceData -> Box
    -> (StockPriceData -> [MovingAverage]) -> Color3 GLfloat -> [GLfloat]
getMovingAverageLines priceData bounds movingAverageFunction color =
  concat lines
  where
    priceRange = getPriceRange priceData
    numElements = numDailyElements priceData
    trim = take numElements
    indices = [0 .. numElements - 1]
    values = trim $ movingAverageFunction priceData
    lines = map (createMovingAverageLine bounds priceRange
        values color numElements) indices

createMovingAverageLine :: Box -> (Float, Float) -> [MovingAverage]
    -> Color3 GLfloat -> Int -> Int -> [GLfloat]
createMovingAverageLine bounds priceRange movingAverages color numElements index
  | index >= length movingAverages = []
  | otherwise = [rightX, rightY] ++ colorList
  where
    colorList = color3ToList color
    (leftX, _, rightX) = getXValues bounds numElements index
    movingAverageValue = movingAverages !! index
    rightY = getY bounds priceRange movingAverageValue

renderLoading :: Resources -> GraphInput -> IO GraphOutput
renderLoading resources
    input@GraphInput
      { alpha = alpha
      , inputState = state
      } = do
  color $ gray4 alpha
  renderCenteredText resources "Loading..."
  return GraphOutput
    { outputState = state
    , isDirty = False
    }

renderError :: Resources -> GraphInput -> String -> IO GraphOutput
renderError resources
    input@GraphInput
      { alpha = alpha
      , inputState = state
      }
    errorMessage =  do
  color $ gray4 alpha
  renderCenteredText resources "ERROR"
  return GraphOutput
    { outputState = state
    , isDirty = False
    }

renderCenteredText :: Resources -> String -> IO ()
renderCenteredText resources text = do
  let textSpec = TextSpec (font resources) 18 text
  textBounds <- measureText textSpec
  preservingMatrix $ do
    let centerX = -(boxWidth textBounds / 2)
        centerY = -(boxHeight textBounds / 2)
    translate $ vector3 centerX centerY 0
    renderText textSpec
