--[[
	Adapted from PolyBool (github.com/voidqk/polybooljs) under the MIT license.
	(c) 2016 Sean Connelly (@voidqk)
	
	Original Lua port by EgoMoose.
	Refactor and optimisations by Elttob.
]]

--[[
	Converts a list of segments into a list of regions, while also removing
	unnecessary vertices.
]]

local Epsilon = require(script.Parent:WaitForChild("Epsilon"))
local Array = require(script.Parent:WaitForChild("Array"))

local function SegmentChainer(segments, buildLog)
	local chains = {}
	local regions = {}

	for _, seg in ipairs(segments) do
		local pt1 = seg.start
		local pt2 = seg.finish
		
		if Epsilon.pointsSame(pt1, pt2) then
			warn('PolyBool: Warning: Zero-length segment detected; your epsilon is probably too small or too large');
			return
		end

		if buildLog then
			buildLog.chainStart(seg)
		end

		-- search for two chains that this segment matches
		local first_match = {
			index = 1, -- zero?
			matches_head = false,
			matches_pt1 = false
		}
		
		local second_match = {
			index = 1, -- zero?
			matches_head = false,
			matches_pt1 = false
		}
		
		local next_match = first_match
		
		local function setMatch(index, matches_head, matches_pt1)
			-- return true if we've matched twice
			next_match.index = index
			next_match.matches_head = matches_head
			next_match.matches_pt1 = matches_pt1
			
			if next_match == first_match then
				next_match = second_match
				return false
			end
			
			next_match = nil
			
			return true -- we've matched twice, we're done here
		end
		
		for i = 1, #chains do
			local chain = chains[i]
			local head  = chain[1]
			local head2 = chain[2]
			local tail  = chain[#chain]
			local tail2 = chain[#chain - 1]
			
			if Epsilon.pointsSame(head, pt1) then
				if setMatch(i, true, true) then
					break
				end
			elseif Epsilon.pointsSame(head, pt2) then
				if setMatch(i, true, false) then
					break
				end
			elseif Epsilon.pointsSame(tail, pt1) then
				if setMatch(i, false, true) then
					break
				end
			elseif Epsilon.pointsSame(tail, pt2) then
				if setMatch(i, false, false) then
					break
				end
			end
		end

		if next_match == first_match then
			-- we didn't match anything, so create a new chain
			chains[#chains + 1] = {pt1, pt2}
			
			if buildLog then
				buildLog.chainNew(pt1, pt2)
			end
			
			continue
		end

		if next_match == second_match then
			-- we matched a single chain

			if buildLog then
				buildLog.chainMatch(first_match.index)
			end

			-- add the other point to the apporpriate finish, and check to see if we've closed the
			-- chain into a loop

			local index = first_match.index
			local pt = first_match.matches_pt1 and pt2 or pt1 -- if we matched pt1, then we add pt2, etc
			local addToHead = first_match.matches_head -- if we matched at head, then add to the head
			
			local chain = chains[index]
			local grow  = chain[#chain]
			local grow2 = chain[#chain - 1]
			local oppo  = chain[1]
			local oppo2 = chain[2]
			
			if addToHead then
				grow, grow2, oppo, oppo2 = oppo, oppo2, grow, grow2
			end
			
			if Epsilon.pointsCollinear(grow2, grow, pt) then
				-- grow isn't needed because it's directly between grow2 and pt:
				-- grow2 ---grow---> pt
				if addToHead then
					if buildLog then
						buildLog.chainRemoveHead(first_match.index, pt)
					end
					
					table.remove(chain, 1)
				else
					if buildLog then
						buildLog.chainRemoveTail(first_match.index, pt)
					end
					
					chain[#chain] = nil
				end
				grow = grow2 -- old grow is gone... new grow is what grow2 was
			end
			
			if Epsilon.pointsSame(oppo, pt) then
				-- we're closing the loop, so remove chain from chains
				table.remove(chains, index)

				if Epsilon.pointsCollinear(oppo2, oppo, grow) then
					-- oppo isn't needed because it's directly between oppo2 and grow:
					-- oppo2 ---oppo--->grow
					if addToHead then
						if buildLog then
							buildLog.chainRemoveTail(first_match.index, grow)
						end
						chain[#chain] = nil
					else
						if buildLog then
							buildLog.chainRemoveHead(first_match.index, grow)
						end
						table.remove(chain, 1)
					end
				end

				if buildLog then
					buildLog.chainClose(first_match.index)
				end
				
				-- we have a closed chain!
				regions[#regions + 1] = chain
				continue
			end

			-- not closing a loop, so just add it to the apporpriate side
			if addToHead then
				if buildLog then
					buildLog.chainAddHead(first_match.index, pt)
				end
				table.insert(chain, 1, pt)
				
			else
				if buildLog then
					buildLog.chainAddTail(first_match.index, pt)
				end
				chain[#chain + 1] = pt
			end
			
			continue
		end

		-- otherwise, we matched two chains, so we need to combine those chains together

		local function reverseChain(index)
			if buildLog then
				buildLog.chainReverse(index)
			end
			Array.reverse(chains[index]) -- gee, that's easy
		end

		local function appendChain(index1, index2)
			-- index1 gets index2 appended to it, and index2 is removed
			local chain1 = chains[index1]
			local chain2 = chains[index2]
			local tail  = chain1[#chain1]
			local tail2 = chain1[#chain1 - 1]
			local head  = chain2[1]
			local head2 = chain2[2]

			if Epsilon.pointsCollinear(tail2, tail, head) then
				-- tail isn't needed because it's directly between tail2 and head
				-- tail2 ---tail---> head
				if buildLog then
					buildLog.chainRemoveTail(index1, tail)
				end
				chain1[#chain1] = nil
				tail = tail2 -- old tail is gone... new tail is what tail2 was
			end

			if Epsilon.pointsCollinear(tail, head, head2) then
				-- head isn't needed because it's directly between tail and head2
				-- tail ---head---> head2
				if buildLog then
					buildLog.chainRemoveHead(index2, head)
				end
				table.remove(chain2, 1)
			end

			if buildLog then
				buildLog.chainJoin(index1, index2)
			end
			chains[index1] = Array.concat(chain1, chain2)
			table.remove(chains, index2)
		end

		local F = first_match.index
		local S = second_match.index

		if buildLog then
			buildLog.chainConnect(F, S)
		end

		local reverseF = #chains[F] < #chains[S] -- reverse the shorter chain, if needed
		if first_match.matches_head then
			if second_match.matches_head then
				if reverseF then
					-- <<<< F <<<< --- >>>> S >>>>
					reverseChain(F)
					-- >>>> F >>>> --- >>>> S >>>>
					appendChain(F, S)
				else
					-- <<<< F <<<< --- >>>> S >>>>
					reverseChain(S);
					-- <<<< F <<<< --- <<<< S <<<<   logically same as:
					-- >>>> S >>>> --- >>>> F >>>>
					appendChain(S, F);
				end
			else
				-- <<<< F <<<< --- <<<< S <<<<   logically same as:
				-- >>>> S >>>> --- >>>> F >>>>
				appendChain(S, F);
			end
		else
			if second_match.matches_head then
				-- >>>> F >>>> --- >>>> S >>>>
				appendChain(F, S)
			else
				if reverseF then
					-- >>>> F >>>> --- <<<< S <<<<
					reverseChain(F)
					-- <<<< F <<<< --- <<<< S <<<<   logically same as:
					-- >>>> S >>>> --- >>>> F >>>>
					appendChain(S, F)
				else
					-- >>>> F >>>> --- <<<< S <<<<
					reverseChain(S)
					-- >>>> F >>>> --- >>>> S >>>>
					appendChain(F, S)
				end
			end
		end
	end

	return regions
end

return SegmentChainer