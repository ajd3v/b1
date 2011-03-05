module B1.Program.Chart.Resources
  ( Resources
    ( Resources
    , font
    , windowWidth
    , windowHeight
    , mousePosition
    )
  , newResources
  , updateKeysPressed
  , isKeyPressed
  , getKeyPressed
  , updateMouseButtonsPressed
  , updateMouseButtonsReleased
  , isMouseButtonPressed
  , isMouseButtonClicked
  , updateMousePosition
  , invertMousePositionY
  , updateWindowSize
  ) where

import Data.Maybe
import Graphics.Rendering.FTGL
import Graphics.Rendering.OpenGL
import Graphics.UI.GLFW

data Resources = Resources
  { font :: Font
  , windowWidth :: GLfloat
  , windowHeight :: GLfloat
  , keysPressed :: [Key]
  , previousKeysPressed :: [Key]
  , mouseButtonsPressed :: [MouseButton]
  , mouseButtonsReleased :: [MouseButton]
  , previousMouseButtonsPressed :: [MouseButton]
  , previousMouseButtonsReleased :: [MouseButton]
  , mousePosition :: (GLfloat, GLfloat)
  , mouseButtonPressCount :: Int
  } deriving (Show, Eq)

newResources :: Font -> Resources
newResources font = Resources
  { font = font
  , windowWidth = 0
  , windowHeight = 0
  , keysPressed = []
  , previousKeysPressed = []
  , mouseButtonsPressed = []
  , mouseButtonsReleased = []
  , previousMouseButtonsPressed = []
  , previousMouseButtonsReleased = []
  , mousePosition = (0, 0)
  , mouseButtonPressCount = 0
  }

updateKeysPressed :: [Key] -> Resources -> Resources
updateKeysPressed keysPressed
    resources@Resources { keysPressed = previousKeysPressed } = resources
  { keysPressed = keysPressed
  , previousKeysPressed = previousKeysPressed
  }

-- TODO: Rename to isKeyReleased
isKeyPressed :: Resources -> Key -> Bool
isKeyPressed
    resources@Resources
      { keysPressed = keysPressed
      , previousKeysPressed = previousKeysPressed
      }
    key = any (== key) keysPressed
        && not (any (== key) previousKeysPressed)

getKeyPressed :: Resources -> [Key] -> Maybe Key
getKeyPressed resources keys =
  case pressedKeys of
    (first:_) -> Just first
    otherwise -> Nothing
  where
    presses = map (isKeyPressed resources) keys
    indexedPresses = zip keys presses
    pressedKeys = map fst $ filter snd indexedPresses 

updateMouseButtonsPressed :: [MouseButton] -> Resources -> Resources
updateMouseButtonsPressed buttonsPressed
    resources@Resources
      { mouseButtonsPressed = previousButtonsPressed
      , mouseButtonPressCount = mouseButtonPressCount
      } =
  resources
    { mouseButtonsPressed = buttonsPressed
    , previousMouseButtonsPressed = previousButtonsPressed
    , mouseButtonPressCount = newMouseButtonPressCount
    }
  where
    newMouseButtonPressCount =
        if any (== ButtonLeft) buttonsPressed
          then mouseButtonPressCount + 1
          else 0

updateMouseButtonsReleased :: [MouseButton] -> Resources -> Resources
updateMouseButtonsReleased buttonsReleased
    resources@Resources
      { mouseButtonsReleased = previousButtonsReleased
      , mouseButtonPressCount = mouseButtonPressCount
      } =
  resources
    { mouseButtonsReleased = buttonsReleased
    , previousMouseButtonsReleased = previousButtonsReleased
    , mouseButtonPressCount = newMouseButtonPressCount 
    }
  where
    newMouseButtonPressCount =
        if any (== ButtonLeft) buttonsReleased
          then 0
          else mouseButtonPressCount

isMouseButtonPressed :: Resources -> MouseButton -> Bool
isMouseButtonPressed
    Resources { mouseButtonsPressed = mouseButtonsPressed }
    button =
  any (== button) mouseButtonsPressed

isMouseButtonClicked :: Resources -> MouseButton -> Bool
isMouseButtonClicked
    resources@Resources
      { mouseButtonsReleased = buttonsReleased
      , previousMouseButtonsReleased = previousButtonsReleased
      }
    button =
  any (== button) buttonsReleased
      && not (any (== button) previousButtonsReleased)

updateMousePosition :: Position -> Resources -> Resources
updateMousePosition (Position x y) resources = resources
  { mousePosition = (fromIntegral x, fromIntegral y)
  }

invertMousePositionY :: Resources -> Resources
invertMousePositionY
    resources@Resources
      { windowHeight = windowHeight
      , mousePosition = (x, y)
      } = 
  resources { mousePosition = (x, windowHeight - y) }

updateWindowSize :: Size -> Resources -> Resources
updateWindowSize (Size width height) resources = resources
  { windowWidth = fromIntegral width
  , windowHeight = fromIntegral height
  }


