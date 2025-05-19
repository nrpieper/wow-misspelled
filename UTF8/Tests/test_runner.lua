if Misspelled.Tests == nil then
    Misspelled.Tests = {}
end

function Misspelled.Tests:RunTests()
    --Run performance tests
    Misspelled.Tests.Performance:RunTests()
    Misspelled.Tests.Misspelled:RunTests()
end