import math

def simulate_crosstab_logic():
    # Simulate the output of terra::crosstab(s, long = TRUE)
    # data format: [class_value, start_jd, end_jd, pixel_count]
    raw_data = [
        [1, 10, 100, 50],
        [1, 10, 100, 50],
        [1, 20, 110, 30],
        [2, 15, 95, 0],
        [2, 15, 95, 40],
        [3, 5, 85, 25],
        [None, 10, 100, 10],
        [1, None, 100, 5],
        [1, 10, None, 5]
    ]

    print("Initial Simulated Crosstab Data:")
    for row in raw_data:
        print(row)

    class_values = [1, 2]

    # 1, 2, 3. Filter and Normalize
    filtered_data = []
    for row in raw_data:
        cv, sj, ej, pc = row
        # !is.na(profile_df$class_value) & !is.na(profile_df$start_jd) & !is.na(profile_df$end_jd) & profile_df$pixel_count > 0
        if cv is not None and sj is not None and ej is not None and pc > 0:
            # profile_df$class_value %in% class_values
            if cv in class_values:
                filtered_data.append(row)

    print("\nAfter Filtering:")
    for row in filtered_data:
        print(row)

    # 4, 5. Type Casting, Total Days, and Final Filter
    final_data = []
    for row in filtered_data:
        cv, sj, ej, pc = row
        # Ensure correct types
        cv = int(cv)
        sj = int(sj)
        ej = int(ej)
        pc = int(pc)
        # Calculate total days
        td = ej - sj + 1
        # Filter total_days > 0
        if td > 0:
            final_data.append([cv, sj, ej, pc, td])

    print("\nFinal Profile Table [cv, sj, ej, pc, td]:")
    for row in final_data:
        print(row)

    # Expectations check
    assert len(final_data) == 4 # [1, 10, 100, 50, 91], [1, 10, 100, 50, 91], [1, 20, 110, 30, 91], [2, 15, 95, 40, 81]
    # Note: R's as.data.frame(crosstab) usually collapses duplicates, but our filtering logic
    # handles them correctly regardless.

    for row in final_data:
        assert row[0] in class_values
        assert row[3] > 0
        assert row[4] > 0
        assert all(v is not None for v in row)

    print("\nLogic Verification Successful!")

if __name__ == "__main__":
    simulate_crosstab_logic()
