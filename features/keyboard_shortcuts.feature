@keyboard @shortcuts
Feature: Keyboard Shortcuts
  As a user
  I want comprehensive keyboard shortcuts
  So that I can work efficiently without using the mouse

  Background:
    Given the application is running
    And a 3D model is loaded

  @file
  Scenario Outline: File operation shortcuts
    When I press <shortcut>
    Then <action> should occur

    Examples:
      | shortcut     | action                           |
      | Cmd+T        | a new tab with example cube opens |
      | Cmd+O        | the file open dialog opens       |
      | Cmd+S        | the model is saved (if modified) |
      | Cmd+Shift+S  | the save as dialog opens         |
      | Cmd+R        | the current file is reloaded     |

  @camera
  Scenario Outline: Camera preset shortcuts
    When I press <shortcut>
    Then the camera should move to <view>

    Examples:
      | shortcut | view                |
      | Cmd+1    | front view          |
      | Cmd+2    | back view           |
      | Cmd+3    | left view           |
      | Cmd+4    | right view          |
      | Cmd+5    | top view            |
      | Cmd+6    | bottom view         |
      | Cmd+0    | reset view          |
      | 7        | home/isometric view |
      | F        | frame model in view |

  @view
  Scenario Outline: View toggle shortcuts
    When I press <shortcut>
    Then <action> should occur

    Examples:
      | shortcut     | action                        |
      | Cmd+I        | info panel toggles            |
      | Cmd+W        | wireframe mode cycles         |
      | Cmd+G        | grid mode cycles              |
      | Cmd+B        | build plate cycles            |
      | Cmd+Shift+X  | slicing panel toggles         |

  @measurement
  Scenario Outline: Measurement shortcuts
    When I press <shortcut>
    Then <action> should occur

    Examples:
      | shortcut     | action                                          |
      | Cmd+D        | distance measurement mode starts                |
      | Cmd+A        | angle measurement mode starts                   |
      | R            | radius measurement mode starts                  |
      | T            | triangle selection mode starts                  |
      | Cmd+M        | material cycles                                 |
      | Cmd+Shift+K  | all measurements are cleared                    |
      | Cmd+Shift+C  | selected/all measurements copied as OpenSCAD    |
      | Cmd+P        | selected/all measurements copied as polygon     |

  @measurement-mode
  Scenario Outline: Measurement mode shortcuts
    Given a measurement mode is active
    When I press <shortcut>
    Then <action> should occur

    Examples:
      | shortcut  | action                               |
      | X         | toggles X-axis constraint or ends measurement |
      | Y         | toggles Y-axis constraint            |
      | Z         | toggles Z-axis constraint            |
      | Option    | toggles direction constraint         |
      | Backspace | removes last point or selected items |
      | Delete    | removes last point or selected items |

  @triangle-select
  Scenario: Paint mode for triangle selection
    Given triangle selection mode is active
    When I hold Cmd and drag the mouse
    Then triangles under the cursor should be continuously selected
    And the camera should not rotate

  @triangle-select
  Scenario: Rectangle selection for triangles
    Given triangle selection mode is active
    When I hold Option+Cmd and drag to draw a selection rectangle
    Then all triangles with vertices inside the rectangle should be selected
    And triangles behind visible triangles should also be selected

  @leveling
  Scenario Outline: Leveling shortcuts
    When I press <shortcut>
    Then <action> should occur

    Examples:
      | shortcut | action                      |
      | Cmd+L    | leveling mode starts        |
      | L        | leveling mode starts        |

  @leveling
  Scenario: Leveling with point selection
    Given leveling mode is active
    When I click on two points on the model
    And I select an axis (X, Y, or Z)
    Then the model should rotate so both points have the same coordinate on that axis

  @tools
  Scenario Outline: Tool shortcuts
    When I press <shortcut>
    Then <action> should occur

    Examples:
      | shortcut | action                      |
      | O        | opens file with go3mf       |
      | Ctrl+C   | quits the application       |

  @escape
  Scenario: Escape key behavior - cancel leveling
    Given leveling mode is active
    When I press Escape
    Then leveling mode should be cancelled

  @escape
  Scenario: Escape key behavior - cancel measurement
    Given a measurement is in progress
    When I press Escape
    Then the measurement should be cancelled

  @escape
  Scenario: Escape key behavior - clear selection
    Given measurements are selected
    When I press Escape
    Then the selection should be cleared

  @escape
  Scenario: Escape key behavior - reset slicing
    Given slicing bounds are active
    And no measurement or selection is active
    When I press Escape
    Then slicing bounds should reset

  @escape
  Scenario: Escape key behavior - reset camera
    Given no measurement, selection, or slicing is active
    When I press Escape
    Then the camera should reset to default view
