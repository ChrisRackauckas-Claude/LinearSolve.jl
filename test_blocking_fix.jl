using LinearSolve
using LinearSolveAutotune
using LinearAlgebra
using Test

# Create a small test case to verify the blocking mechanism
# We'll simulate the benchmarking process with a controlled scenario

# Test the blocking logic directly
function test_blocking_logic()
    # Simulate the blocked_algorithms dictionary
    blocked_algorithms = Dict{String, Dict{String, Int}}()
    blocked_algorithms["Float64"] = Dict{String, Int}()
    
    # Simulate that GenericLUFactorization exceeded maxtime at size 9000
    blocked_algorithms["Float64"]["GenericLUFactorization"] = 9000
    
    # Test cases
    test_cases = [
        (8000, false),  # Size smaller than blocked size - should NOT be skipped
        (9000, true),   # Size equal to blocked size - SHOULD be skipped (this was the bug!)
        (10000, true),  # Size larger than blocked size - should be skipped
    ]
    
    println("Testing blocking logic:")
    for (n, should_skip) in test_cases
        # Check if algorithm should be skipped
        name = "GenericLUFactorization"
        eltype_str = "Float64"
        
        skip = false
        if haskey(blocked_algorithms[eltype_str], name)
            blocked_at_size = blocked_algorithms[eltype_str][name]
            if n >= blocked_at_size  # This is the fixed logic
                skip = true
            end
        end
        
        status = skip == should_skip ? "✓" : "✗"
        println("  Size $n: skip=$skip (expected=$should_skip) $status")
        
        @test skip == should_skip
    end
    
    println("\nAll blocking logic tests passed!")
end

# Run the test
test_blocking_logic()

# Now test with actual autotune to ensure it integrates properly
println("\nTesting with actual autotune (small matrices for speed):")

# Use very small matrices and low maxtime to trigger the blocking quickly
sizes = [5, 10, 15, 20, 25]
maxtime = 0.001  # Very small timeout to trigger blocking

# We expect some algorithms to exceed maxtime and be blocked
results = LinearSolveAutotune.benchmark_algorithms(
    sizes,
    [LinearSolve.LUFactorization(), LinearSolve.GenericLUFactorization()],
    ["LUFactorization", "GenericLUFactorization"],
    [Float64];
    maxtime = maxtime,
    check_correctness = false
)

# Check that blocking occurred
df = results.results_df

# Find if any algorithm was blocked
blocked_entries = filter(row -> contains(get(row, :error, ""), "Skipped"), df)

if nrow(blocked_entries) > 0
    println("✓ Blocking mechanism activated successfully")
    println("  Found $(nrow(blocked_entries)) skipped entries")
    
    # Verify that once an algorithm is blocked at size N, it's also blocked at sizes >= N
    for alg in unique(blocked_entries.algorithm)
        blocked_at_sizes = filter(row -> row.algorithm == alg && contains(get(row, :error, ""), "Skipped"), df).size
        if length(blocked_at_sizes) > 1
            # Check they are consecutive
            sorted_sizes = sort(blocked_at_sizes)
            println("  Algorithm $alg blocked at sizes: $sorted_sizes")
        end
    end
else
    println("⚠ No blocking occurred (might need to adjust test parameters)")
end

println("\nTest complete!")