module B1.Program.Chart.Resources
  ( Resources (..)
  , newResources
  , updateKeysPressed
  , isKeyPressed
  , getKeyPressed
  , updateMouseButtonsPressed
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
  , previousMouseButtonsPressed :: [MouseButton]
  , mousePosition :: (GLfloat, GLfloat)
  } deriving (Show, Eq)

newResources :: Font -> Resources
newResources font = Resources
  { font = font
  , windowWidth = 0
  , windowHeight = 0
  , keysPressed = []
  , previousKeysPressed = []
  , mouseButtonsPressed = []
  , previousMouseButtonsPressed = []
  , mousePosition = (0, 0)
  }

updateKeysPressed :: [Key] -> Resources -> Resources
updateKeysPressed keysPressed
    resources@Resources { keysPressed = previousKeysPressed } = resources
  { keysPressed = keysPressed
  , previousKeysPressed = previousKeysPressed
  }

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
    resources@Resources { mouseButtonsPressed = previousButtonsPressed } =
  resources
    { mouseButtonsPressed = buttonsPressed
    , previousMouseButtonsPressed = previousButtonsPressed
    }

isMouseButtonClicked :: Resources -> MouseButton -> Bool
isMouseButtonClicked
    resources@Resources
      { mouseButtonsPressed = buttonsPressed
      , previousMouseButtonsPressed = previousButtonsPressed
      }
    button = any (== button) buttonsPressed
        && not (any (== button) previousButtonsPressed)

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


