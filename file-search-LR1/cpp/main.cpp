#include <stdio.h>
#include <math.h>
#include <time.h>
#include <aboba.h>

double term(double x, int k) {
    double numerator = 1.0;
    double denominator = 1.0;

    __asm__ volatile (
        // Вычисляем числитель: x^(2k)
        "fld1\n\t"
        "mov %[k], %%ecx\n\t"
        "test %%ecx, %%ecx\n\t"
        "jz .skip_numerator\n\t"
        "fldl %[x]\n\t"
        ".loop_numerator:\n\t"
        "fmul %%st(0), %%st(1)\n\t"
        "fmul %%st(0), %%st(1)\n\t"
        "loop .loop_numerator\n\t"
        "fstp %%st(0)\n\t"
        ".skip_numerator:\n\t"
        "fstpl %[numerator]\n\t"

        // Вычисляем знаменатель: (2k)!
        "fld1\n\t"
        "mov %[k], %%ecx\n\t"
        "test %%ecx, %%ecx\n\t"
        "jz .skip_denominator\n\t"
        ".loop_denominator:\n\t"
        "mov %%ecx, %%eax\n\t"
        "add %%eax, %%eax\n\t"
        "push %%rax\n\t"
        "fildl (%%rsp)\n\t"
        "fmulp %%st(1)\n\t"
        "pop %%rax\n\t"
        "loop .loop_denominator\n\t"
        ".skip_denominator:\n\t"
        "fstpl %[denominator]\n\t"
        : [numerator] "=m" (numerator), [denominator] "=m" (denominator)
        : [x] "m" (x), [k] "m" (k)
        : "rax", "rcx", "st", "st(1)", "cc"
    );

    return numerator / denominator;
}

// Функция вычисления S(x) = sum(x^(2k)/(2k)!)
double calculate_S(double x, int iterations) {
    double sum = 0.0;
    for (int k = 0; k <= iterations; k++) {
        sum += term(x, k);
    }
    return sum;
}

// Функция вычисления Y(x) = (e^x + e^(-x))/2
double calculate_Y(double x) {
    return (exp(x) + exp(-x)) / 2.0;
}

int main() {
    double x = 1.0;  // Значение x
    int max_iterations = 10000;
    int report_interval = 500;
    
    double y = calculate_Y(x);  // Вычисляем Y(x) один раз
    
    printf("Calculation for x=%.2f with %d iterations\n", x, max_iterations);
    printf("Iterations\tS(x)\t\t\tY(x)\t\t\tDifference\tTime (sec)\n");
    printf("----------------------------------------------------------------------------\n");
    
    FILE *data_file = fopen("results.txt", "w");
    if (!data_file) {
        perror("Failed to open results file");
        return 1;
    }
    fprintf(data_file, "Iterations\tS(x)\t\tY(x)\t\tDifference\tTime\n");

    for (int n = report_interval; n <= max_iterations; n += report_interval) {
        clock_t start = clock();
        double s = calculate_S(x, n);
        clock_t end = clock();
        double time_spent = (double)(end - start) / CLOCKS_PER_SEC;
        double difference = fabs(y - s);
        
        printf("%9d\t%.15f\t%.15f\t%.15f\t%.6f\n", 
              n, s, y, difference, time_spent);
        fprintf(data_file, "%d\t%.15f\t%.15f\t%.15f\t%.6f\n", 
               n, s, y, difference, time_spent);
    }

    // Финальный расчет
    clock_t start = clock();
    double final_s = calculate_S(x, max_iterations);
    clock_t end = clock();
    double total_time = (double)(end - start) / CLOCKS_PER_SEC;
    double final_diff = fabs(y - final_s);
    
    printf("\nFinal results after %d iterations:\n", max_iterations);
    printf("S(x) = %.15f\n", final_s);
    printf("Y(x) = %.15f\n", y);
    printf("Difference = %.15f\n", final_diff);
    printf("Total computation time: %.6f seconds\n", total_time);
    
    fclose(data_file);
    return 0;
}
