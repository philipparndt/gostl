@camera @navigation
Feature: Camera Navigation
  As a user
  I want to navigate the 3D view using mouse and keyboard controls
  So that I can examine the model from any angle

  Background:
    Given the application is running
    And a 3D model is loaded

  @mouse
  Scenario: Rotate camera with left-click drag
    When I left-click and drag on the viewport
    Then the camera should rotate around the model
    And the rotation should follow the drag direction
    And the rotation should be free orbital rotation

  @mouse
  Scenario: Pan camera with shift-click drag
    When I hold Shift and left-click and drag on the viewport
    Then the camera should pan horizontally and vertically
    And the model should appear to move in the drag direction

  @mouse
  Scenario: Pan camera with middle-mouse drag
    When I middle-click and drag on the viewport
    Then the camera should pan horizontally and vertically
    And the behavior should be identical to shift-click drag

  @mouse
  Scenario: Zoom with scroll wheel
    When I scroll the mouse wheel
    Then the camera should zoom in or out
    And scroll up should zoom in
    And scroll down should zoom out
    And the zoom sensitivity should be adjustable

  @zoom-limits
  Scenario: Camera distance clamping
    When I zoom in to the maximum extent
    Then the camera distance should not go below 1.0 units
    When I zoom out to the maximum extent
    Then the camera distance should not exceed 1000.0 units
