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
