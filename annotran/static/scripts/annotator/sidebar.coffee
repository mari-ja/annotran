###
Copyright (c) 2013-2014 Hypothes.is Project and contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
###

extend = require('extend')
raf = require('raf')
Hammer = require('hammerjs')
Annotator = require('annotator')
xpathRange = Annotator.Range

Host = require('./host')

# Minimum width to which the frame can be resized.
MIN_RESIZE = 280

module.exports = class Sidebar extends Host
  options:
    Document: {}
    TextSelection: {}
    SentenceSelection: {}
    Substitution: {}
    CSSModify: {}
    BucketBar:
      container: '.annotator-frame'
    Toolbar:
      container: '.annotator-frame'

  loadedAnnotations: []
  renderFrame: null
  gestureState: null


  constructor: (element, options) ->
    super
    this.hide()

    if options.firstRun
      this.on 'panelReady', => this.show()

    if @plugins.BucketBar?
      @plugins.BucketBar.element.on 'click', (event) => this.show()

    if @plugins.Toolbar?
      this._setupGestures()

    this._setupSidebarEvents()

  _setupDocumentEvents: ->
    @element.on 'click', (event) =>
      if !@selectedTargets?.length
        # don't hide sidebar
        return this
    return this

  _setupSidebarEvents: ->
    @crossframe.on('show', this.show.bind(this))
    @crossframe.on('hide', this.hide.bind(this))

    # Return this for chaining
    this

  _setupGestures: ->
    $toggle = @toolbar.find('[name=sidebar-toggle]')

    # Prevent any default gestures on the handle
    $toggle.on('touchmove', (event) -> event.preventDefault())

    # Set up the Hammer instance and handlers
    mgr = new Hammer.Manager($toggle[0])
    .on('panstart panend panleft panright', this.onPan)
    .on('swipeleft swiperight', this.onSwipe)

    # Set up the gesture recognition
    pan = mgr.add(new Hammer.Pan({direction: Hammer.DIRECTION_HORIZONTAL}))
    swipe = mgr.add(new Hammer.Swipe({direction: Hammer.DIRECTION_HORIZONTAL}))
    swipe.recognizeWith(pan)

    # Set up the initial state
    this._initializeGestureState()

    # Return this for chaining
    this

  _initializeGestureState: ->
    @gestureState =
      initial: null
      final: null

  # Schedule any changes needed to update the sidebar layout.
  _updateLayout: ->
    # Only schedule one frame at a time
    return if @renderFrame

    # Schedule a frame
    @renderFrame = raf =>
      @renderFrame = null  # Clear the schedule

      # Process the resize gesture
      if @gestureState.final isnt @gestureState.initial
        m = @gestureState.final
        w = -m
        @frame.css('margin-left', "#{m}px")
        if w >= MIN_RESIZE then @frame.css('width', "#{w}px")

  onPan: (event) =>
    switch event.type
      when 'panstart'
        # Initialize the gesture state
        this._initializeGestureState()
        # Immadiate response
        @frame.addClass 'annotator-no-transition'
        # Escape iframe capture
        @frame.css('pointer-events', 'none')
        # Set origin margin
        @gestureState.initial = parseInt(getComputedStyle(@frame[0]).marginLeft)

      when 'panend'
        # Re-enable transitions
        @frame.removeClass 'annotator-no-transition'
        # Re-enable iframe events
        @frame.css('pointer-events', '')
        # Snap open or closed
        if @gestureState.final <= -MIN_RESIZE
          this.show()
        else
          this.hide()
        # Reset the gesture state
        this._initializeGestureState()

      when 'panleft', 'panright'
        return unless @gestureState.initial?
        # Compute new margin from delta and initial conditions
        m = @gestureState.initial
        d = event.deltaX
        @gestureState.final = Math.min(Math.round(m + d), 0)
        # Start updating
        this._updateLayout()

  onSwipe: (event) =>
    switch event.type
      when 'swipeleft'
        this.show()
      when 'swiperight'
        this.hide()

  show: ->
    @frame.css 'margin-left': "#{-1 * @frame.width()}px"
    @frame.removeClass 'annotator-collapsed'

    if @toolbar?
      @toolbar.find('[name=sidebar-toggle]')
      .removeClass('h-icon-chevron-left')
      .addClass('h-icon-chevron-right')

  hide: ->
    @frame.css 'margin-left': ''
    @frame.addClass 'annotator-collapsed'

    if @toolbar?
      @toolbar.find('[name=sidebar-toggle]')
      .removeClass('h-icon-chevron-right')
      .addClass('h-icon-chevron-left')

  createAnnotation: (annotation = {}) ->

    elementsClaimed = []

    # iterate over all ranges in this.loadedAnnotations
    for annotation in this.loadedAnnotations

      # first, package up the target selector into a form we can understand
      for target_selector in annotation.target[0].selector
        if target_selector.type == "RangeSelector"
          packager = {
            start: target_selector.startContainer
            startOffset: target_selector.startOffset
            end: target_selector.endContainer
            endOffset: target_selector.endOffset
          }

      # convert this to a range in the current document and extract the start and end points
      range = new xpathRange.SerializedRange(packager).normalize(document.body)
      elementsClaimed.push(range.toRange().getBoundingClientRect())


    selection = Annotator.Util.getGlobal().getSelection()
    ranges = for i in [0...selection.rangeCount]
      r = selection.getRangeAt(0)
      if r.collapsed then continue else r

    for r in ranges
      packager = {
        start: r.startContainer
        startOffset: r.startOffset
        end: r.endContainer
        endOffset: r.endOffset
      }

    # convert this to a range in the current document and extract the start and end points
    range = new xpathRange.NormalizedRange(packager)
    selection_box = range.toRange().getBoundingClientRect()

    for claimed in elementsClaimed
      isClaimed = !(claimed.right < selection_box.left ||
                  claimed.left > selection_box.right ||
                  claimed.bottom < selection_box.top ||
                  claimed.top > selection_box.bottom)

      if isClaimed
        break

    if isClaimed
      alert("You cannot create a new translation here since the currently selected region is already translated by you. Please edit or delete your existing translation instead.")
    else
      super
      this.show() unless annotation.$highlight

  showAnnotations: (annotations) ->
    super
    this.show()
