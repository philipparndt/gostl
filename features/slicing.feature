@slicing
Feature: Model Slicing and Cross-Sections
  As a user
  I want to slice the model along different axes
  So that I can view internal structures and cross-sections

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Toggle slicing panel
    When I press Cmd+Shift+S
    Then the slicing panel should toggle visibility
    And the panel should appear at the bottom-right of the screen
    And the panel should be 300 pixels wide

  Scenario: Slicing panel UI elements
    When the slicing panel is visible
    Then I should see sliders for X, Y, and Z axes
    And each axis should have min and max sliders
    And the sliders should be color-coded (Red/Green/Blue for X/Y/Z)
    And numeric values should be displayed for each slider

  Scenario: Adjust X-axis slicing bounds
    When I adjust the X-axis min slider
    Then the model should be clipped from the minimum X bound
    When I adjust the X-axis max slider
    Then the model should be clipped from the maximum X bound
    And only geometry within the X bounds should be visible

  Scenario: Adjust Y-axis slicing bounds
    When I adjust the Y-axis min slider
    Then the model should be clipped from the minimum Y bound
    When I adjust the Y-axis max slider
    Then the model should be clipped from the maximum Y bound
    And only geometry within the Y bounds should be visible

  Scenario: Adjust Z-axis slicing bounds
    When I adjust the Z-axis min slider
    Then the model should be clipped from the minimum Z bound
    When I adjust the Z-axis max slider
    Then the model should be clipped from the maximum Z bound
    And only geometry within the Z bounds should be visible

  Scenario: Multi-axis slicing
    When I adjust sliders on multiple axes
    Then the model should be clipped by all active bounds simultaneously
    And only geometry within all bounds should be visible

  Scenario: Fill cross-sections
    Given slicing is active on at least one axis
    When I enable "Fill Cross-Sections"
    Then the cut areas should be filled with a solid surface
    And the fill should show the internal cross-section

  Scenario: Show cutting planes
    Given slicing is active on at least one axis
    When I enable "Show Planes"
    Then semi-transparent cutting planes should be displayed
    And the planes should show where the model is being cut

  Scenario: Active plane highlighting
    When I am actively dragging a slice slider
    Then only the plane for the selected axis should be visible
    And other planes should be hidden during adjustment

  Scenario: Colored cut edges
    When I slice the model on any axis
    Then cut edges should be displayed in the axis color
    And X-axis cuts should show red edges
    And Y-axis cuts should show green edges
    And Z-axis cuts should show blue edges

  Scenario: Reset slicing bounds
    Given slicing is active on one or more axes
    When I press R (while slicing panel is focused)
    Then all slice bounds should reset to full model extent
    And the entire model should become visible again

  Scenario: Reset slicing with Escape
    Given slicing is active on one or more axes
    When I press Escape
    Then all slice bounds should reset to full model extent

  Scenario: Automatic bounds from model
    When the slicing panel is opened
    Then the slider ranges should be set from the model bounding box
    And the initial values should show the full model extent

  Scenario: Throttled mesh updates
    When I rapidly drag a slice slider
    Then the mesh should update at a maximum of 30 frames per second
    And this ensures responsive UI during adjustment

  Scenario: Deferred wireframe clipping
    When I adjust a slice slider
    Then the unclipped wireframe should update immediately
    And the clipped wireframe should update asynchronously
    And the clipped version should appear after a brief delay

  Scenario: Info panel shows slicing status
    When slicing is active and triangles are clipped
    Then the info panel should show visible vs total triangle count
    And the format should be "Triangles: visible / total"
    And the text should be orange to indicate slicing is active
