@camera @presets
Feature: Camera Presets
  As a user
  I want to quickly switch to predefined camera angles
  So that I can view the model from standard orientations

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Front view
    When I press Cmd+1
    Then the camera should move to the front view
    And the camera should face the XZ plane
    And the model should be viewed from the front

  Scenario: Back view
    When I press Cmd+2
    Then the camera should move to the back view
    And the camera should face the opposite direction from front
    And the model should be viewed from behind

  Scenario: Left view
    When I press Cmd+3
    Then the camera should move to the left view
    And the camera should be positioned to the left of the model

  Scenario: Right view
    When I press Cmd+4
    Then the camera should move to the right view
    And the camera should be positioned to the right of the model

  Scenario: Top view
    When I press Cmd+5
    Then the camera should move to the top view
    And the camera should be looking down at the model
    And the XZ plane should be visible from above

  Scenario: Bottom view
    When I press Cmd+6
    Then the camera should move to the bottom view
    And the camera should be looking up at the model
    And the XZ plane should be visible from below

  Scenario: Home view
    When I press 7
    Then the camera should move to the default isometric view
    And the model should be visible from an angled perspective

  Scenario: Reset view with Cmd+0
    Given I have rotated and zoomed the camera
    When I press Cmd+0
    Then the camera should return to the default position
    And the model should be framed in view

  Scenario: Reset view with Escape
    Given I have rotated and zoomed the camera
    And no measurement or selection is active
    When I press Escape
    Then the camera should return to the default position

  Scenario: Frame model in view
    Given the model is partially outside the viewport
    When I press F
    Then the camera should adjust to frame the entire model
    And the model should be fully visible
