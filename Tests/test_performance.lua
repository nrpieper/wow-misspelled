if Misspelled.Tests == nil then
    Misspelled.Tests = {}
end

Misspelled.Tests.Performance = {}

-- Compare the performance of the WoW built in function: strlenutf8, with the utf8len
function Misspelled.Tests.Performance:TestUTF8lenPerformance()
    print("Missspelled.Tests Starting: Performance:TestUTF8lenPerformance - utf8len() vs strlenutf8()")
    --do lots of stuff

    local beginTime
    local x
    local timeUsed

    debugprofilestart()

    beginTime = debugprofilestop()
    for i = 1, 10000 do
        x = string.utf8lenold("Testä")
    end
    timeUsed = debugprofilestop() - beginTime
    print("(string.utf8lenold) Calls: 10,000   Time used: " .. timeUsed.. "(ms)")


    beginTime = debugprofilestop()
    for i = 1, 10000 do
        x = string.utf8len("Testä")
    end
    timeUsed = debugprofilestop() - beginTime
    print("(string.utf8len) Calls: 10,000   Time used: " .. timeUsed.. "(ms)")


    beginTime = debugprofilestop()
    for i = 1, 10000 do
        x = strlenutf8("Testä")
    end
    timeUsed = debugprofilestop() - beginTime
    print("(strlenutf8) Calls: 10,000   Time used: " .. timeUsed.. "(ms)")

    print("Missspelled.Tests Done: Performance:TestUTF8lenPerformance")
end

function Misspelled.Tests.Performance:RunTests()
    Misspelled.Tests.Performance:TestUTF8lenPerformance()
end



