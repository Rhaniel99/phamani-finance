<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('transactions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('account_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('category_id')->constrained()->restrictOnDelete();
            $table->foreignUuid('recurring_id')->nullable()->constrained('recurring_transactions')->nullOnDelete();
            $table->foreignUuid('installment_id')->nullable()->constrained()->nullOnDelete();
            $table->unsignedSmallInteger('installment_number')->nullable();
            $table->string('name');
            $table->text('description')->nullable();
            $table->enum('type', ['income', 'expense']);
            $table->decimal('amount', 12, 2);
            $table->date('date');
            $table->timestamps();

            $table->index(['user_id', 'date']);
            $table->index('type');
            $table->index('category_id');
            $table->index('account_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transactions');
    }
};
