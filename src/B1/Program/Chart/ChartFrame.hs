module B1.Program.Chart.ChartFrame
  ( FrameInput(..)
  , FrameOutput(..)
  , FrameOptions(..)
  , FrameState
  , drawChartFrame
  , newFrameState
  , cleanFrameState
  ) where

import Control.Monad
import Data.Maybe
import Graphics.Rendering.OpenGL

import B1.Control.TaskManager
import B1.Data.Range
import B1.Data.Symbol
import B1.Graphics.Rendering.OpenGL.Box
import B1.Graphics.Rendering.OpenGL.BufferManager
import B1.Graphics.Rendering.OpenGL.Utils
import B1.Program.Chart.Animation
import B1.Program.Chart.Dirty
import B1.Program.Chart.Resources

import qualified B1.Program.Chart.Chart as C
import qualified B1.Program.Chart.Header as H
import qualified B1.Program.Chart.Instructions as I

data FrameInput = FrameInput
  { bounds :: Box
  , alpha :: GLfloat
  , maybeSymbolRequest :: Maybe Symbol
  , inputState :: FrameState
  }

data FrameOutput = FrameOutput
  { outputState :: FrameState
  , isDirty :: Dirty
  , buttonClickedSymbol :: Maybe Symbol -- ^ Symbol when button clicked
  , otherClickedSymbol :: Maybe Symbol -- ^ Symbol when other area clicked
  , refreshedSymbol :: Maybe Symbol -- ^ Symbol when refresh button clicked
  , selectedSymbol :: Maybe Symbol -- ^ Symbol when a request is fulfilled
  , draggedSymbol :: Maybe Symbol -- ^ Symbol when dragging starts
  }

data FrameOptions = FrameOptions
  { chartOptions :: C.ChartOptions
  , inScaleAnimation :: Animation (GLfloat, Dirty)
  , inAlphaAnimation :: Animation (GLfloat, Dirty)
  , outScaleAnimation :: Animation (GLfloat, Dirty)
  , outAlphaAnimation :: Animation (GLfloat, Dirty)
  }

data FrameState = FrameState
  { options :: FrameOptions
  , createChart :: Symbol -> IO Content
  , maybeCurrentFrame :: Maybe Frame
  , maybePreviousFrame :: Maybe Frame
  }

data Frame = Frame
  { content :: Content
  , scaleAnimation :: Animation (GLfloat, Dirty)
  , alphaAnimation :: Animation (GLfloat, Dirty)
  }

data Content = Instructions | Chart Symbol C.ChartState

newFrameState :: FrameOptions -> TaskManager -> Maybe Symbol -> IO FrameState
newFrameState
    options@FrameOptions
      { chartOptions = chartOptions
      }
    taskManager
    maybeSymbol = do
  let createChart = newChartContent chartOptions taskManager
  content <- case maybeSymbol of
    Just symbol -> createChart symbol
    _ -> return Instructions
  return FrameState
    { options = options
    , createChart = createChart
    , maybeCurrentFrame = Just Frame
      { content = content
      , scaleAnimation = incomingScaleAnimation
      , alphaAnimation = incomingAlphaAnimation
      }
    , maybePreviousFrame = Nothing
    }

cleanFrameState :: Resources -> FrameState -> IO FrameState
cleanFrameState
    resources
    state@FrameState
      { maybeCurrentFrame = maybeCurrentFrame
      , maybePreviousFrame = maybePreviousFrame
      } = do
  let cleanContent :: Resources -> Maybe Frame -> IO (Maybe Frame)
      cleanContent _ Nothing = return Nothing
      cleanContent resources (Just frame) = do
        newContent <- cleanFrameContent resources $ content frame
        return $ Just (frame { content = newContent })
  newCurrentFrame <- cleanContent resources maybeCurrentFrame
  newPreviousFrame <- cleanContent resources maybePreviousFrame
  return state
    { maybeCurrentFrame = newCurrentFrame
    , maybePreviousFrame = newPreviousFrame
    }

drawChartFrame :: Resources -> FrameInput -> IO FrameOutput
drawChartFrame resources
    FrameInput
      { bounds = bounds
      , alpha = alpha
      , maybeSymbolRequest = maybeSymbolRequest
      , inputState = inputState
      } = do

  (revisedState, selectedSymbol) <- handleSymbolRequest
      maybeSymbolRequest inputState

  let FrameState
        { maybeCurrentFrame = maybeCurrentFrame
        , maybePreviousFrame = maybePreviousFrame
        } = revisedState
      render = renderFrame resources bounds alpha
  (nextMaybeCurrentFrame, isCurrentDirty, buttonClickedSymbol,
      refreshedSymbol, otherClickedSymbol, draggedSymbol)
          <- render maybeCurrentFrame True
  (nextMaybePreviousFrame, isPreviousDirty, _, _, _, _)
      <- render maybePreviousFrame False

  let outputState = inputState
        { maybeCurrentFrame = nextMaybeCurrentFrame
        , maybePreviousFrame = nextMaybePreviousFrame
        }
      isDirty = isCurrentDirty || isPreviousDirty
  return FrameOutput
    { outputState = outputState
    , isDirty = isDirty
    , buttonClickedSymbol = buttonClickedSymbol
    , otherClickedSymbol = otherClickedSymbol
    , refreshedSymbol = refreshedSymbol
    , selectedSymbol = selectedSymbol
    , draggedSymbol = draggedSymbol
    }

handleSymbolRequest :: Maybe Symbol -> FrameState
    -> IO (FrameState, Maybe Symbol)
handleSymbolRequest Nothing state = return (state, Nothing)
handleSymbolRequest (Just symbol)
    state@FrameState
      { options = options
      , createChart = createChart
      , maybeCurrentFrame = maybeCurrentFrame
      } = do
  chartContent <- createChart symbol
  let outputState = state
        { maybeCurrentFrame = newCurrentFrame options chartContent
        , maybePreviousFrame = newPreviousFrame options maybeCurrentFrame
        } 
  return (outputState, Just symbol)

newChartContent :: C.ChartOptions -> TaskManager -> Symbol -> IO Content
newChartContent chartOptions taskManager symbol = do
  state <- C.newChartState chartOptions taskManager symbol
  return $ Chart symbol state

newCurrentFrame :: FrameOptions -> Content -> Maybe Frame
newCurrentFrame options content = Just Frame
  { content = content
  , scaleAnimation = inScaleAnimation options
  , alphaAnimation = inAlphaAnimation options
  }

newPreviousFrame :: FrameOptions -> Maybe Frame -> Maybe Frame
newPreviousFrame _ Nothing = Nothing
newPreviousFrame options (Just frame) = Just $ frame 
  { scaleAnimation = outScaleAnimation options
  , alphaAnimation = outAlphaAnimation options
  }

renderFrame :: Resources -> Box -> GLfloat -> Maybe Frame -> Bool
    -> IO (Maybe Frame, Dirty, Maybe Symbol, Maybe Symbol, Maybe Symbol,
        Maybe Symbol)
renderFrame _ _ _ Nothing _ =
  return (Nothing, False, Nothing, Nothing, Nothing, Nothing)
renderFrame resources bounds alpha (Just frame) isCurrentFrame = do
  let currentContent = content frame
      currentScaleAnimation = scaleAnimation frame
      currentAlphaAnimation = alphaAnimation frame
      scaleAmount = (fst . current) currentScaleAnimation
      alphaAmount = (fst . current) currentAlphaAnimation
      finalAlpha = min alpha alphaAmount
      removeInvisiblePreviousFrame = not isCurrentFrame && finalAlpha <= 0.0
  if removeInvisiblePreviousFrame
    then do
      cleanFrameContent resources currentContent
      return (Nothing, False, Nothing, Nothing, Nothing, Nothing)
    else
      preservingMatrix $ do
        scale3 scaleAmount scaleAmount 1
        (nextContent, isContentDirty, buttonClickedSymbol, refreshedSymbol, 
            otherClickedSymbol, draggedSymbol) <- renderContent resources bounds
                currentContent finalAlpha
        let nextScaleAnimation = next currentScaleAnimation
            nextAlphaAnimation = next currentAlphaAnimation
            nextFrame = frame
              { content = nextContent
              , scaleAnimation = nextScaleAnimation
              , alphaAnimation = nextAlphaAnimation
              }
            isDirty = isContentDirty
                || (snd . current) currentScaleAnimation
                || (snd . current) currentAlphaAnimation
        return (Just nextFrame, isDirty, buttonClickedSymbol, refreshedSymbol,
            otherClickedSymbol, draggedSymbol)

-- TODO: Use type classes instead of special cases...
cleanFrameContent :: Resources -> Content -> IO Content
cleanFrameContent resources (Chart symbol state) = do
  newState <- C.cleanChartState resources state
  return $ Chart symbol newState
cleanFrameContent _ content = return content

renderContent :: Resources -> Box -> Content -> GLfloat
    -> IO (Content, Dirty, Maybe Symbol, Maybe Symbol, Maybe Symbol,
        Maybe Symbol)

renderContent resources bounds Instructions alpha = do
  let input = I.InstructionsInput
        { I.bounds = bounds
        , I.alpha = alpha
        }
  output <- I.drawInstructions resources input
  return (Instructions, I.isDirty output, Nothing, Nothing, Nothing, Nothing)

renderContent resources bounds (Chart symbol state) alpha = do
  let input = C.ChartInput
        { C.bounds = boxShrink 5 bounds
        , C.alpha = alpha
        , C.inputState = state
        }
  output <- C.drawChart resources input
  return (Chart symbol (C.outputState output),
      C.isDirty output,
      C.buttonClickedSymbol output,
      C.refreshedSymbol output,
      C.otherClickedSymbol output,
      C.draggedSymbol output)

