@visualization @build-plate
Feature: Build Plate Visualization
  As a user
  I want to display 3D printer build plate outlines
  So that I can verify if my model fits on a specific printer

  Background:
    Given the application is running
    And a 3D model is loaded

  Scenario: Default build plate is off
    When a model is first loaded
    Then no build plate should be displayed

  Scenario: Cycle build plate with keyboard
    When I press Cmd+B
    Then the build plate should cycle to the next available printer
    And the cycle should include all available build plates

  @bambu-lab
  Scenario Outline: Display Bambu Lab printer build plates
    When I select the "<printer>" build plate
    Then a build plate outline should be displayed
    And the build volume should be <dimensions> mm

    Examples:
      | printer  | dimensions     |
      | X1C      | 256 x 256 x 256 |
      | P1S      | 256 x 256 x 256 |
      | A1       | 256 x 256 x 256 |
      | A1 mini  | 180 x 180 x 180 |
      | H2D      | 450 x 450 x 450 |

  @prusa
  Scenario Outline: Display Prusa printer build plates
    When I select the "<printer>" build plate
    Then a build plate outline should be displayed
    And the build volume should be <dimensions> mm

    Examples:
      | printer | dimensions       |
      | MK4     | 250 x 210 x 220  |
      | Mini    | 180 x 180 x 180  |

  @voron
  Scenario Outline: Display Voron printer build plates
    When I select the "<printer>" build plate
    Then a build plate outline should be displayed
    And the build volume should be <dimensions> mm

    Examples:
      | printer | dimensions       |
      | V0      | 120 x 120 x 120  |
      | 2.4     | 350 x 350 x 350  |

  @creality
  Scenario: Display Creality Ender 3 build plate
    When I select the "Ender 3" build plate
    Then a build plate outline should be displayed
    And the build volume should be 220 x 220 x 250 mm

  Scenario: Build plate visual representation
    When a build plate is selected
    Then a wireframe outline of the plate bounds should be displayed
    And a semi-transparent volume fill should be shown
    And the plate should use a blue color scheme

  Scenario: Toggle plate orientation
    When a build plate is selected
    Then I should be able to toggle the plate orientation
    And "Bottom" orientation places the plate on the XZ plane (vertical model)
    And "Back" orientation places the plate on the XY plane (horizontal model)

  Scenario: Select build plate from menu
    When I open the View menu
    And I navigate to the Build Plate submenu
    Then I should see printer categories: "Bambu Lab", "Prusa", "Voron", "Creality"
    And each category should list available printers
    When I select a printer
    Then the corresponding build plate should be displayed
