<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Tags livres (ex.: "iFood", "Amazon", "viagem-floripa"), pessoais de cada usuário.
 * As tabelas já existiam (vieram do Lukisa, sem uso); aqui ganham o slug:
 * nome normalizado (minúsculas, sem acento) — evita "ifood", "iFood" e "IFOOD" separados.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tags', function (Blueprint $table) {
            $table->string('slug', 40)->nullable()->after('name');
        });

        foreach (DB::table('tags')->get(['id', 'name']) as $tag) {
            DB::table('tags')->where('id', $tag->id)->update([
                'slug' => Str::of($tag->name)->ascii()->lower()->squish()->limit(40, '')->value(),
            ]);
        }

        Schema::table('tags', function (Blueprint $table) {
            $table->dropUnique(['user_id', 'name']);
            $table->unique(['user_id', 'slug']);
        });

        Schema::table('transaction_tags', function (Blueprint $table) {
            $table->index('tag_id');
        });
    }

    public function down(): void
    {
        Schema::table('transaction_tags', function (Blueprint $table) {
            $table->dropIndex(['tag_id']);
        });

        Schema::table('tags', function (Blueprint $table) {
            $table->dropUnique(['user_id', 'slug']);
            $table->unique(['user_id', 'name']);
            $table->dropColumn('slug');
        });
    }
};
