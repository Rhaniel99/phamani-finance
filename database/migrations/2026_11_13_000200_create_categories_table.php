<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('categories', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->uuid('parent_id')->nullable();
            $table->string('name', 100);
            $table->enum('type', ['income', 'expense', 'both'])->default('expense');
            $table->string('color', 20)->nullable();
            $table->string('icon', 30)->nullable();
            $table->timestamps();

            $table->unique(['user_id', 'name']);
        });

        // FK auto-referente em etapa separada: no PostgreSQL o Laravel só cria a
        // chave primária depois das FKs declaradas no create(), então referenciar
        // a própria tabela ali falha com "no unique constraint matching given keys".
        Schema::table('categories', function (Blueprint $table) {
            $table->foreign('parent_id')->references('id')->on('categories')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('categories');
    }
};
