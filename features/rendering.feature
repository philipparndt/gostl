@rendering
Feature: 3D Rendering
  As a user
  I want high-quality 3D rendering
  So that I can clearly see and analyze models

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Anti-aliased rendering
    Then the model should be rendered with 4x MSAA anti-aliasing
    And edges should appear smooth without jagged artifacts

  Scenario: Depth testing
    Then proper Z-order rendering should be applied
    And closer geometry should correctly occlude farther geometry

  Scenario: Material-based coloring
    When a material is selected
    Then the model should be rendered with the material's color
    And the specular reflection should match the material's glossiness

  Scenario: Lighting
    Then the model should be lit with appropriate lighting
    And surfaces facing the light should be brighter
    And surfaces facing away should be in shadow

  Scenario: Transparent rendering
    When transparent elements are present (like cutting planes)
    Then they should be rendered with proper transparency
    And depth should be handled correctly for transparent surfaces

  Scenario: Edge rendering
    When wireframe mode is enabled
    Then edges should be rendered as instanced cylinders
    And edge thickness should be consistent across view angles
    And the cylinder's radius should be authored in pixels, which the shader scales to world space

  @annotations
  Scenario: Annotations keep their size on screen
    Given a measurement has been taken
    Then measurement lines should be drawn a few pixels wide, whatever the model measures
    And the cubes marking picked points should cover the same patch of screen wherever they sit
    And a marker should never swallow the feature it marks

  @clipping
  Scenario: Clip planes follow the camera
    Then the near and far planes should be derived from the camera's distance
    And a metre-scale model should be neither clipped away nor starved of depth precision

  @face-orientation
  Scenario: Face orientation coloring
    When face orientation mode is enabled (Cmd+Shift+F)
    Then front-facing surfaces should be rendered in teal (#3e999f)
    And back-facing surfaces should be rendered in gold/yellow (#eab700)
    And this helps identify inverted normals in the model
