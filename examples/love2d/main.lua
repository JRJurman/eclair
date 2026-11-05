local fontSize = 24
local margin = 30

local readout = ''

local textValue = 'The brown fox'
local routeValue = 1
local rateValue = 1.0
local volumeValue = 1.0

local possibleRouteDisplayValues = { 'Prefer Screen Reader', 'Screen Reader Only', 'Synthesizer Only', 'Off' }
local possibleRouteSpeechValues = { 'preferscreenreader', 'screenreaderonly', 'synthesizeronly', 'off' }

local selection = -1

local instructions = 'Press Enter to speak text. Press down to change text and options.'

function love.load()
	local largeFont = love.graphics.newFont(fontSize)
	love.graphics.setFont(largeFont)
	setSelection(0)
end

function love.update()
end

function love.draw()
	love.graphics.clear()

	love.graphics.print("FPS: "..tostring(love.timer.getFPS( )), 650, 10)

	local baseX = 10
	local valueX = 200

	local baseY = 10
	setColorForSection(0)
	love.graphics.printf(instructions, baseX, baseY + (margin * 0), 550, 'left')

	baseY = 100
	setColorForSection(1)
	love.graphics.printf('Text', baseX, baseY + (margin * 0), 300, 'left')
	love.graphics.printf(textValue, valueX, baseY + (margin * 0), 600, 'left')

	setColorForSection(2)
	love.graphics.printf('Route', baseX, baseY + (margin * 1), 300, 'left')
	love.graphics.printf('< '..possibleRouteDisplayValues[routeValue]..' >', valueX, baseY + (margin * 1), 300, 'left')

	setColorForSection(3)
	love.graphics.printf('Rate', baseX, baseY + (margin * 2), 300, 'left')
	love.graphics.printf('< '..rateValue..' >', valueX, baseY + (margin * 2), 300, 'left')

	setColorForSection(4)
	love.graphics.printf('Volume', baseX, baseY + (margin * 3), 300, 'left')
	love.graphics.printf('< '..volumeValue..' >', valueX, baseY + (margin * 3), 300, 'left')

	baseY = 250
	setColorForSection(5)
	love.graphics.printf('output', baseX, baseY + (margin * 0), 300, 'left')
	love.graphics.printf(love.speech.getOutput(), valueX, baseY + (margin * 0), 300, 'left')

	setColorForSection(6)
	love.graphics.printf('backend', baseX, baseY + (margin * 1), 300, 'left')
	love.graphics.printf(love.speech.getBackendName() or '', valueX, baseY + (margin * 1), 300, 'left')

	baseY = 350
	love.graphics.setColor(1, 1, 1)
	love.graphics.printf('Readout: '..readout, baseX, baseY + (margin * 0), 750, 'left')
end

function love.keyreleased(key)
	-- read text
	if key == 'return' then
		updateReadout(textValue)
		return
	end

	-- change selection
	if key == 'up' and selection > 0 then
		setSelection(selection - 1)
		return
	end

	if key == 'down' and selection < 6 then
		setSelection(selection + 1)
		return
	end

	-- text
	if selection == 1 then
		if key == 'left' or key == 'right' then
			-- ignore
		elseif key == 'backspace' then
			lastCharacter = string.sub(textValue, #textValue, #textValue + 1)
			textValue = string.sub(textValue, 1, #textValue - 1)
			updateReadout(lastCharacter)
		elseif key == 'space' then
			textValue = textValue..' '
			updateReadout('space')
		else
			textValue = textValue..key
			updateReadout(key)
		end
	end

	-- route
	if selection == 2 then
		if key == 'left' and routeValue > 1 then
			routeValue = routeValue - 1
			love.speech.setRoute(possibleRouteSpeechValues[routeValue])
			print('love.speech.setRoute('..possibleRouteSpeechValues[routeValue]..')')
			updateReadout(possibleRouteDisplayValues[routeValue])
		end
		if key == 'right' and routeValue < 4 then
			routeValue = routeValue + 1
			love.speech.setRoute(possibleRouteSpeechValues[routeValue])
			print('love.speech.setRoute('..possibleRouteSpeechValues[routeValue]..')')
			updateReadout(possibleRouteDisplayValues[routeValue])
		end
	end

	-- rate
	if selection == 3 then
		if key == 'left' and rateValue > 0.5 then
			rateValue = rateValue - 0.5
			love.speech.setRate(rateValue)
			print('love.speech.setRate('..rateValue..')')
			updateReadout(rateValue)
		end
		if key == 'right' and rateValue < 4.0 then
			rateValue = rateValue + 0.5
			love.speech.setRate(rateValue)
			print('love.speech.setRate('..rateValue..')')
			updateReadout(rateValue)
		end
	end

	-- volume
	if selection == 4 then
		if key == 'left' and volumeValue > 0.1 then
			volumeValue = volumeValue - 0.1
			love.speech.setVolume(volumeValue)
			print('love.speech.setVolume('..volumeValue..')')
			updateReadout(volumeValue)
		end
		if key == 'right' and volumeValue < 1.0 then
			volumeValue = volumeValue + 0.1
			love.speech.setVolume(volumeValue)
			print('love.speech.setVolume('..volumeValue..')')
			updateReadout(volumeValue)
		end
	end
end

function setSelection(newSelection)
	selection = newSelection

	-- update the readout based on the section
	if selection == 0 then
		updateReadout(instructions)
	elseif selection == 1 then
		updateReadout('Text, type to update, current value: '..textValue)
	elseif selection == 2 then
		updateReadout('Route, press left or right to change, current value: '..possibleRouteDisplayValues[routeValue])
	elseif selection == 3 then
		updateReadout('Rate, press left or right to change, current value: '..rateValue)
	elseif selection == 4 then
		updateReadout('Volume, press left or right to change, current value: '..volumeValue)
	elseif selection == 5 then
		print('love.speech.getOutput()')
		updateReadout('Output, current value: '..love.speech.getOutput())
	elseif selection == 6 then
		print('love.speech.getBackendName()')
		updateReadout('Backend, current value: '..love.speech.getBackendName())
	end
end

function setColorForSection(targetSection)
	if selection == targetSection then
		love.graphics.setColor(240/256, 200/256, 140/256)
	else
		love.graphics.setColor(1, 1, 1)
	end
end

function updateReadout(text)
	readout = text
	love.speech.speak(text, true)
	print('love.speech.speak(\''..text..'\')')
end
